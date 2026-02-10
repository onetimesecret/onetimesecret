# lib/onetime/utils/email_hash.rb
#
# frozen_string_literal: true

require 'openssl'

module Onetime
  module Utils
    # EmailHash - HMAC-based email hashing for cross-region federation
    #
    # Computes deterministic HMAC-SHA256 hashes of normalized email addresses.
    # Used to identify accounts across regions without exposing email addresses.
    #
    # Security properties:
    # - One-way: Email cannot be recovered from hash
    # - Deterministic: Same email + same secret = same hash (across regions)
    # - Immutable: Hash computed at subscription time, never updated
    #
    # The hash is truncated to 128 bits (32 hex chars) for:
    # - Sufficient collision resistance for federation use case
    # - Reasonable storage size in Redis and Stripe metadata
    #
    # @see https://github.com/onetimesecret/onetimesecret/issues/2471
    #
    module EmailHash
      extend self

      # Length of the truncated hash in hex characters (128 bits)
      HASH_LENGTH = 32

      # Compute HMAC-SHA256 hash of normalized email
      #
      # Email normalization:
      # - Lowercase (case-insensitive matching)
      # - Trim whitespace
      #
      # @param email [String] Email address to hash
      # @return [String, nil] 32-character hex hash, or nil if email is empty
      # @raise [Onetime::Problem] If FEDERATION_SECRET is not configured
      #
      # @example
      #   EmailHash.compute('Alice@Example.com')  #=> "a1b2c3..."
      #   EmailHash.compute('alice@example.com')  #=> "a1b2c3..." (same hash)
      #   EmailHash.compute('')                   #=> nil
      #
      def compute(email)
        return nil if email.to_s.strip.empty?

        normalized = normalize_email(email)
        secret     = fetch_secret

        digest = OpenSSL::Digest.new('sha256')
        hmac   = OpenSSL::HMAC.hexdigest(digest, secret, normalized)
        hmac[0...HASH_LENGTH]
      end

      # Check if two emails produce the same hash
      #
      # Useful for verification without exposing the actual hash value.
      #
      # @param email1 [String] First email
      # @param email2 [String] Second email
      # @return [Boolean] True if emails hash to same value
      #
      def same_hash?(email1, email2)
        hash1 = compute(email1)
        hash2 = compute(email2)
        return false if hash1.nil? || hash2.nil?

        # Use secure comparison to prevent timing attacks
        secure_compare(hash1, hash2)
      end

      private

      # Normalize email for consistent hashing
      #
      # @param email [String] Raw email address
      # @return [String] Normalized email (lowercase, trimmed)
      #
      def normalize_email(email)
        email.to_s.downcase.strip
      end

      # Fetch the HMAC secret from configuration
      #
      # Uses FEDERATION_SECRET environment variable via config.
      # This is separate from the main encryption secret for security isolation.
      #
      # @return [String] The HMAC secret
      # @raise [Onetime::Problem] If secret is not configured
      #
      def fetch_secret
        # Try environment variable first (allows testing without full OT boot)
        secret = ENV.fetch('FEDERATION_SECRET', nil)

        # Fall back to config if env var not set and OT.conf is available
        if secret.to_s.empty? && defined?(OT) && OT.respond_to?(:conf) && OT.conf
          secret = OT.conf.dig('features', 'regions', 'federation_hmac_secret')
        end

        if secret.to_s.empty?
          raise Onetime::Problem, 'FEDERATION_SECRET not configured'
        end

        secret
      end

      # Secure string comparison to prevent timing attacks
      #
      # @param a [String] First string
      # @param b [String] Second string
      # @return [Boolean] True if strings are equal
      #
      def secure_compare(a, b)
        return false if a.nil? || b.nil?
        return false if a.bytesize != b.bytesize

        # Use OpenSSL's secure compare if available (Ruby 2.5+)
        if OpenSSL.respond_to?(:secure_compare)
          OpenSSL.secure_compare(a, b)
        else
          # Fallback: constant-time comparison
          a.bytes.zip(b.bytes).reduce(0) { |r, (x, y)| r | (x ^ y) }.zero?
        end
      end
    end
  end
end
