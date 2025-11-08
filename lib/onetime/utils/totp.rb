# lib/onetime/utils/totp.rb
#
# frozen_string_literal: true

require 'rotp'

module Onetime
  module Utils
    # TOTP utility for testing and debugging MFA
    class TOTP
      # Generate a TOTP code from a secret
      #
      # @param secret [String] Base32-encoded secret
      # @param issuer [String] Optional issuer name (default: OneTimeSecret)
      # @param drift [Integer] Optional drift window in seconds (default: 15)
      # @return [Hash] Hash with current code, previous code, next code, and metadata
      #
      # @example
      #   result = Onetime::Utils::TOTP.generate("JBSWY3DPEHPK3PXP")
      #   puts result[:current_code]  # => "123456"
      #   puts result[:valid_for]     # => 23 (seconds remaining)
      #
      def self.generate(secret, issuer: 'OneTimeSecret', drift: 15)
        totp = ROTP::TOTP.new(secret, issuer: issuer)

        current_time = Time.now.to_i
        interval = totp.interval # Usually 30 seconds

        {
          secret: secret,
          secret_sample: "#{secret[0..3]}...#{secret[-4..-1]}",
          issuer: issuer,
          current_code: totp.now,
          previous_code: totp.at(current_time - interval),
          next_code: totp.at(current_time + interval),
          current_time: current_time,
          interval: interval,
          valid_for: interval - (current_time % interval),
          drift_window: drift,
        }
      end

      # Verify a TOTP code against a secret
      #
      # @param secret [String] Base32-encoded secret
      # @param code [String] 6-digit TOTP code to verify
      # @param drift [Integer] Drift window in seconds (default: 15)
      # @return [Hash] Verification result with details
      #
      def self.verify(secret, code, drift: 15)
        totp = ROTP::TOTP.new(secret, issuer: 'OneTimeSecret')

        valid_at = totp.verify(code, drift_behind: drift, drift_ahead: drift)

        {
          secret: secret,
          secret_sample: "#{secret[0..3]}...#{secret[-4..-1]}",
          code: code,
          valid: !valid_at.nil?,
          valid_at: valid_at,
          expected_code: totp.now,
          match: code == totp.now,
        }
      end

      # Compute HMAC secret from raw secret (matches Rodauth's implementation)
      #
      # @param raw_secret [String] Raw base32-encoded secret
      # @param hmac_secret [String] HMAC secret key from config
      # @return [String] HMAC-secured version of the secret
      #
      def self.compute_hmac(raw_secret, hmac_secret = nil)
        hmac_secret ||= ENV['HMAC_SECRET']

        if hmac_secret.nil? || hmac_secret.empty?
          raise 'HMAC_SECRET environment variable must be set'
        end

        # This mirrors Rodauth's otp_hmac_secret method
        # Rodauth: decodes base32 → HMAC-SHA256 → encode to base32
        require 'rotp/base32'
        require 'openssl'

        # Decode the raw secret from base32 to bytes
        raw_bytes = ROTP::Base32.decode(raw_secret)

        # Compute HMAC-SHA256 (Rodauth uses SHA256)
        hmac_bytes = OpenSSL::HMAC.digest(OpenSSL::Digest::SHA256.new, hmac_secret, raw_bytes)

        # Encode back to base32 using standard encoding
        ROTP::Base32.encode(hmac_bytes)
      end
    end
  end
end
