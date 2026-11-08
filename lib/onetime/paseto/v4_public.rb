# lib/onetime/paseto/v4_public.rb
#
# frozen_string_literal: true

require 'base64'
require 'json'
require 'openssl'

module Onetime
  module Paseto
    # PASETO v4.public: Ed25519 signatures over the Pre-Authentication
    # Encoding of the header, payload, footer and implicit assertion.
    #
    #   token = "v4.public." || base64url(payload || signature) ["." base64url(footer)]
    #   signature = Ed25519.sign(sk, PAE("v4.public.", payload, footer, implicit))
    #
    # Only the public (signed, unencrypted) purpose of version 4 is
    # implemented: it is what API bearer tokens need. The primitive is
    # OpenSSL's Ed25519 (openssl gem >= 3.0, Ruby >= 3.1); no further gem is
    # involved. Correctness is pinned by the official PASETO test vectors in
    # spec/fixtures/paseto/v4.json (spec/unit/onetime/paseto/v4_public_spec.rb).
    #
    # This module is deliberately free of claims semantics: it signs and
    # verifies opaque payload bytes. Registered claims, key selection by `kid`
    # and the clock live in Onetime::Paseto::AccessToken.
    #
    # Spec: https://github.com/paseto-standard/paseto-spec/blob/master/docs/01-Protocol-Versions/Version4.md
    module V4Public
      HEADER            = 'v4.public.'
      SIGNATURE_BYTES   = 64
      ED25519_KEY_BYTES = 32

      # Upper bound on an incoming token. Issued tokens are a few hundred
      # bytes; anything larger is refused before any decoding work.
      MAX_TOKEN_BYTES = 4096

      # Unpadded base64url (RFC 4648 §5). PASETO forbids padding; a token
      # carrying `=` or any other character is malformed, not "close enough".
      BASE64URL = /\A[A-Za-z0-9_-]*\z/

      # The three signed parts of a parsed token, before signature verification.
      #
      #   message   the payload bytes (UTF-8 JSON when it was issued by us)
      #   signature the 64 Ed25519 signature bytes
      #   footer    the decoded footer bytes, '' when the token has none
      Parsed = Data.define(:message, :signature, :footer)

      class << self
        # @param private_key [OpenSSL::PKey::PKey] an Ed25519 private key
        # @param payload [String] the payload bytes (usually a JSON object)
        # @param footer [String] optional footer bytes (authenticated, not encrypted)
        # @param implicit [String] optional implicit assertion (authenticated, never transmitted)
        # @return [String] the token
        def sign(private_key, payload, footer: '', implicit: '')
          payload   = payload.to_s.b
          footer    = footer.to_s.b
          pre_auth  = pae(HEADER, payload, footer, implicit.to_s.b)
          signature = private_key.sign(nil, pre_auth)
          raise Error, 'Ed25519 signature has an unexpected length' unless signature.bytesize == SIGNATURE_BYTES

          token  = HEADER + encode(payload + signature)
          token += ".#{encode(footer)}" unless footer.empty?
          token
        end

        # Split a token into its signed parts without verifying anything.
        # The footer is the only part a caller may read before verification,
        # and only to choose a key (see .footer_kid).
        #
        # @param token [String]
        # @return [Parsed]
        # @raise [MalformedToken]
        def parse(token)
          raise MalformedToken, 'token is not a string' unless token.is_a?(String)
          raise MalformedToken, 'token too long' if token.bytesize > MAX_TOKEN_BYTES
          raise MalformedToken, 'unsupported header' unless token.start_with?(HEADER)

          rest                = token.byteslice(HEADER.bytesize, token.bytesize - HEADER.bytesize)
          body, footer, extra = rest.split('.', 3)
          raise MalformedToken, 'too many segments' unless extra.nil?
          raise MalformedToken, 'empty payload' if body.nil? || body.empty?

          signed = decode(body)
          raise MalformedToken, 'payload shorter than a signature' if signed.bytesize <= SIGNATURE_BYTES

          message   = signed.byteslice(0, signed.bytesize - SIGNATURE_BYTES)
          signature = signed.byteslice(signed.bytesize - SIGNATURE_BYTES, SIGNATURE_BYTES)
          Parsed.new(message: message, signature: signature, footer: footer.nil? ? ''.b : decode(footer))
        end

        # Verify a token against one public key.
        #
        # @param public_key [OpenSSL::PKey::PKey] an Ed25519 public key
        # @param token [String, Parsed]
        # @param implicit [String] the implicit assertion the token was signed with
        # @return [Array(String, String)] the payload and footer bytes, both UTF-8
        # @raise [MalformedToken, InvalidSignature]
        def verify(public_key, token, implicit: '')
          parsed   = token.is_a?(Parsed) ? token : parse(token)
          pre_auth = pae(HEADER, parsed.message, parsed.footer, implicit.to_s.b)

          valid = begin
            public_key.verify(nil, parsed.signature, pre_auth)
          rescue OpenSSL::PKey::PKeyError
            false
          end
          raise InvalidSignature, 'signature verification failed' unless valid

          [utf8(parsed.message), utf8(parsed.footer)]
        end

        # Read the `kid` out of a footer without trusting anything else in
        # it. The footer is not verified yet when this runs, so the only use
        # of its content is a dictionary lookup against keys we hold.
        #
        # @param footer [String] raw footer bytes
        # @return [String, nil] a well-formed key identifier, or nil
        def footer_kid(footer)
          return nil if footer.nil? || footer.empty?
          return nil if footer.bytesize > MAX_FOOTER_BYTES

          parsed = JSON.parse(utf8(footer), max_nesting: 2)
          return nil unless parsed.is_a?(Hash)

          kid = parsed['kid']
          kid if kid.is_a?(String) && KID_FORMAT.match?(kid)
        rescue JSON::ParserError, MalformedToken
          nil
        end

        # Pre-Authentication Encoding: a length-prefixed, unambiguous
        # concatenation. LE64 is a 64-bit little-endian unsigned integer with
        # the most significant bit cleared.
        #
        # @param pieces [Array<String>]
        # @return [String]
        def pae(*pieces)
          pieces.each_with_object(le64(pieces.length).b) do |piece, out|
            out << le64(piece.bytesize) << piece.b
          end
        end

        # @param seed [String] 32 raw bytes
        # @return [OpenSSL::PKey::PKey] the Ed25519 private key for that seed
        def private_key_from_seed(seed)
          raise ArgumentError, 'Ed25519 seed must be 32 bytes' unless seed.to_s.bytesize == ED25519_KEY_BYTES

          OpenSSL::PKey.new_raw_private_key('ED25519', seed.b)
        end

        # @param raw [String] 32 raw public key bytes
        # @return [OpenSSL::PKey::PKey]
        def public_key_from_raw(raw)
          raise ArgumentError, 'Ed25519 public key must be 32 bytes' unless raw.to_s.bytesize == ED25519_KEY_BYTES

          OpenSSL::PKey.new_raw_public_key('ED25519', raw.b)
        end

        def encode(bytes)
          Base64.urlsafe_encode64(bytes, padding: false)
        end

        def decode(str)
          raise MalformedToken, 'invalid base64url' unless BASE64URL.match?(str)

          Base64.urlsafe_decode64(str)
        rescue ArgumentError
          raise MalformedToken, 'invalid base64url'
        end

        private

        MAX_FOOTER_BYTES = 1024
        KID_FORMAT       = /\A[A-Za-z0-9_-]{1,128}\z/
        private_constant :MAX_FOOTER_BYTES, :KID_FORMAT

        def le64(n)
          raise ArgumentError, 'PAE length exceeds 2^63' if n >= (1 << 63)

          [n].pack('Q<')
        end

        def utf8(bytes)
          str = bytes.dup.force_encoding(Encoding::UTF_8)
          raise MalformedToken, 'payload is not valid UTF-8' unless str.valid_encoding?

          str
        end
      end
    end
  end
end
