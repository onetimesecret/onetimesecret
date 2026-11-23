# lib/onetime/paseto/keyring.rb
#
# frozen_string_literal: true

require 'digest'
require_relative '../key_derivation'
require_relative 'v4_public'

module Onetime
  module Paseto
    # Hex characters of SHA-256(raw public key) that make up a `kid`.
    KID_HEX_CHARS = 16

    # One Ed25519 key pair and its identifier.
    #
    # The identifier (`kid`) is a function of the public key alone -- the
    # first 16 hex characters of its SHA-256 -- so it reveals nothing about
    # the seed and needs no counter or clock to stay unambiguous across
    # rotations. It travels in the token footer so verification can pick the
    # key before checking the signature.
    #
    # A verification-only key has no private half (`signing?` is false).
    Key = Data.define(:kid, :public_key, :private_key) do
      # @param seed [String] 32 raw bytes (an HKDF output)
      # @return [Key] a signing key
      def self.from_seed(seed)
        private_key = V4Public.private_key_from_seed(seed)
        public_key  = V4Public.public_key_from_raw(private_key.raw_public_key)
        new(kid: kid_for(public_key), public_key: public_key, private_key: private_key)
      end

      # @param public_key [OpenSSL::PKey::PKey]
      # @return [String]
      def self.kid_for(public_key)
        Digest::SHA256.hexdigest(public_key.raw_public_key)[0, KID_HEX_CHARS]
      end

      def signing?
        !private_key.nil?
      end

      # The same key without its private half.
      def verification_only
        with(private_key: nil)
      end

      # Never print key material: Runtime.to_h and exception reports can
      # carry this object into logs.
      def inspect
        "#<#{self.class.name} kid=#{kid}#{' signing' if signing?}>"
      end
      alias_method :to_s, :inspect
    end

    # The keys the v3 API bearer tokens are signed and verified with.
    #
    # Everything is derived from the root SECRET with HKDF
    # (Onetime::KeyDerivation, purpose :paseto_signing), the same way the
    # session, identifier and Familia encryption keys are: no additional key
    # material to generate, back up or inject, and the Ed25519 seed is never
    # stored anywhere. Only the current SECRET verifies bearer tokens.
    # SECRET_PREVIOUS stays available for ciphertext decryption; retaining
    # an old encryption key must not retain its power to authenticate API
    # requests. Rotating SECRET retires previously issued bearer tokens.
    class Keyring
      attr_reader :signing_key

      # @param secret [String] the current root SECRET
      # @return [Keyring]
      def self.derive(secret)
        raise ArgumentError, 'secret must not be empty' if secret.to_s.empty?

        signing_key = Key.from_seed(Onetime::KeyDerivation.derive(secret, :paseto_signing))
        new(signing_key)
      end

      # @param signing_key [Key] the key new tokens are signed with
      def initialize(signing_key)
        raise ArgumentError, 'signing key must carry a private key' unless signing_key.signing?

        @signing_key = signing_key
        @keys        = { signing_key.kid => signing_key.verification_only }
        @keys.freeze
        freeze
      end

      # @param kid [String, nil]
      # @return [Key, nil] a verification-only key, or nil for an unknown kid
      def verification_key(kid)
        return nil if kid.nil?

        @keys[kid]
      end

      # @return [Array<String>] the current key identifier
      def kids
        [signing_key.kid]
      end

      def inspect
        "#<#{self.class.name} signing=#{signing_key.kid} accepted=#{kids.inspect}>"
      end
      alias to_s inspect
    end
  end
end
