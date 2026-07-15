# lib/onetime/session/codec.rb
#
# frozen_string_literal: true

require 'base64'
require 'openssl'
require 'familia'

module Onetime
  # Canonical session-blob codec — the SINGLE definition of the session at-rest
  # format:
  #
  #   base64(iv[12] + auth_tag[16] + AES-256-GCM(JSON(data)))--hmac
  #
  # Both the live Rack store ({Onetime::Session}, the writer) and the session
  # admin read verbs ({Onetime::Operations::Sessions::Store}, the reader) build a
  # SessionCodec from the same session secret, so encoder and decoder can never
  # drift. That drift is exactly the defect this closes: the colonel Sessions
  # console read every value with a plain `JSON.parse`, which fails on the
  # encrypted blob, so it rendered every session — authenticated ones included —
  # as an opaque `_raw` string with no identity fields.
  #
  # Standalone class (not nested under the Rack-subclass {Onetime::Session}) so
  # it carries no request coupling and both sides can require it independently
  # without a load cycle.
  #
  # Security posture (preserved from the original inline implementation):
  # - HMAC is verified with a constant-time compare BEFORE any decrypt.
  # - AES-256-GCM's auth tag is a second, independent tamper check.
  # - {#decode} NEVER calls Marshal.load and NEVER raises — a value that is not
  #   an authentic session blob returns nil so the caller can fall back.
  class SessionCodec
    # 12-byte IV + 16-byte GCM auth tag; anything shorter can't be a payload.
    MIN_ENCRYPTED_BYTES = 28

    attr_reader :encryption_key_raw

    # Build a codec from the running app config, resolving the session secret
    # with the SAME fallback {Onetime::Session} uses (session secret, then the
    # site secret). Returns nil when neither is set so read callers can degrade
    # to the legacy/`_raw` path rather than raising. The plain {.new} stays pure
    # (secret in, no globals) for the writer and for tests.
    #
    # @return [SessionCodec, nil]
    def self.from_config
      cfg    = Onetime.respond_to?(:session_config) ? Onetime.session_config : nil
      secret = cfg && cfg['secret']
      secret = Onetime.conf.dig('site', 'secret') if secret.to_s.empty? && Onetime.respond_to?(:conf)
      return nil if secret.to_s.empty?

      new(secret)
    rescue StandardError
      nil
    end

    # @param secret [String] the session master secret; both subkeys are
    #   HKDF-derived from it (RFC 5869), matching {Onetime::Session}.
    def initialize(secret)
      raise ArgumentError, 'session secret is required' if secret.to_s.empty?

      @secret             = secret
      @hmac_key           = derive_key('hmac')
      @encryption_key_raw = [derive_key('encryption')].pack('H*')
    end

    # Derive a purpose-specific subkey as hex. Parity with the original
    # Session#derive_key so callers (and the session tryout) see one behaviour.
    def derive_key(purpose)
      require 'onetime/key_derivation'
      Onetime::KeyDerivation.derive_session_subkey(@secret, purpose)
    end

    def compute_hmac(data)
      OpenSSL::HMAC.hexdigest('SHA256', @hmac_key, data)
    end

    # Constant-time HMAC check (prevents timing attacks). Returns false on any
    # type/size mismatch before the compare.
    def valid_hmac?(data, hmac)
      expected = compute_hmac(data)
      return false unless hmac.is_a?(String) && expected.is_a?(String)
      return false unless hmac.bytesize == expected.bytesize

      Rack::Utils.secure_compare(expected, hmac)
    end

    # AES-256-GCM encrypt → `iv + auth_tag + ciphertext` (binary).
    def encrypt_data(plaintext)
      cipher     = OpenSSL::Cipher.new('aes-256-gcm')
      cipher.encrypt
      cipher.key = @encryption_key_raw

      iv         = cipher.random_iv
      cipher.iv  = iv
      ciphertext = cipher.update(plaintext) + cipher.final

      iv + cipher.auth_tag + ciphertext
    end

    # AES-256-GCM decrypt. Returns the plaintext, or nil when the input is too
    # short, the auth tag fails, or any cipher error occurs.
    def decrypt_data(encrypted_data)
      return nil if encrypted_data.nil? || encrypted_data.bytesize < MIN_ENCRYPTED_BYTES

      cipher          = OpenSSL::Cipher.new('aes-256-gcm')
      cipher.decrypt
      cipher.key      = @encryption_key_raw
      cipher.iv       = encrypted_data[0, 12]
      cipher.auth_tag = encrypted_data[12, 16]

      cipher.update(encrypted_data[28..]) + cipher.final
    rescue OpenSSL::Cipher::CipherError
      nil
    end

    # Serialize a session hash to the signed at-rest blob.
    #
    # @param hash [Hash]
    # @return [String] `base64(...)--hmac`
    def encode(hash)
      json    = Familia::JsonSerializer.dump(hash)
      encoded = Base64.strict_encode64(encrypt_data(json))
      "#{encoded}--#{compute_hmac(encoded)}"
    end

    # Parse a signed at-rest blob back to its session hash. Returns nil when
    # `stored_data` is not an authentic session blob (wrong shape, bad HMAC, bad
    # base64, failed decrypt, or non-JSON plaintext). NEVER raises and NEVER
    # Marshal.loads — the caller uses nil to fall back (e.g. to a bounded `_raw`
    # preview).
    #
    # @param stored_data [String, nil]
    # @return [Hash, nil]
    def decode(stored_data)
      return nil if stored_data.nil?

      data, hmac = stored_data.split('--', 2)
      return nil unless hmac && valid_hmac?(data, hmac)

      binary = begin
        Base64.strict_decode64(data)
      rescue ArgumentError
        nil
      end
      return nil unless binary

      plaintext = decrypt_data(binary)
      return nil unless plaintext

      parsed = Familia::JsonSerializer.parse(plaintext)
      parsed.is_a?(Hash) ? parsed : nil
    rescue StandardError
      nil
    end
  end
end
