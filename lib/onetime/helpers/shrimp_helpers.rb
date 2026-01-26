# lib/onetime/helpers/shrimp_helpers.rb
#
# frozen_string_literal: true

require 'rack/protection'
require 'securerandom'
require 'openssl'
require 'base64'

module Onetime
  module Helpers
    # CSRF token helpers compatible with Rack::Protection::AuthenticityToken
    #
    # This module provides a unified interface for CSRF token generation and
    # validation using the same algorithm as Rack::Protection.
    #
    # Key points:
    # - Tokens are stored in session[:csrf] (symbol key, per Rack::Protection convention)
    # - The token returned by shrimp_token is MASKED (XOR + base64)
    # - Validation handles unmasking and constant-time comparison
    # - Fully interoperable with Rack::Protection::AuthenticityToken middleware
    #
    module ShrimpHelpers
      TOKEN_LENGTH = 32
      SESSION_KEY  = :csrf

      # Get the current CSRF token (masked for use in forms/headers)
      #
      # Uses Rack::Protection::AuthenticityToken.token() which returns a
      # masked version of the raw token stored in session[:csrf].
      #
      # @return [String] Masked CSRF token safe for inclusion in HTML/headers
      def shrimp_token
        Rack::Protection::AuthenticityToken.token(session)
      end

      # Verify submitted CSRF token and regenerate if valid
      #
      # Validates using the same algorithm as Rack::Protection:
      # - Unmasking XOR'd tokens
      # - Constant-time comparison
      # - Both masked and unmasked token formats
      #
      # @param submitted_token [String] Token from form/header
      # @return [Boolean] true if valid
      # @raise [Onetime::FormError] if token is invalid
      def verify_shrimp!(submitted_token)
        return true if skip_shrimp_check?

        return false if submitted_token.to_s.empty?

        valid = valid_csrf_token?(session, submitted_token.to_s)

        if valid
          regenerate_shrimp! # Prevent replay attacks
          OT.ld "[shrimp-success] Valid token for #{current_customer.custid}"
        else
          OT.ld "[shrimp-fail] Invalid token for #{current_customer.custid}"
          raise Onetime::FormError, 'Security validation failed'
        end

        true
      end

      def add_shrimp
        regenerate_shrimp!
      end

      # Regenerate the CSRF token (for replay attack prevention)
      #
      # Generates a new random token, invalidating the old one.
      def regenerate_shrimp!
        session[SESSION_KEY] = SecureRandom.urlsafe_base64(TOKEN_LENGTH, padding: false)
      end

      # Extract CSRF token from request headers or parameters
      def extract_shrimp_token
        # Check headers first (for AJAX), then form parameter
        request.env['HTTP_X_SHRIMP_TOKEN'] ||
          request.env['HTTP_X_CSRF_TOKEN'] ||  # Standard header for compatibility
          request.env['HTTP_ONETIME_SHRIMP'] || # Legacy header
          params['shrimp']
      end

      # Check if CSRF verification should be skipped for this request
      def skip_shrimp_check?
        # Skip for safe HTTP methods
        return true if %w[GET HEAD OPTIONS TRACE].include?(request.request_method)

        # Skip for API requests with different auth (if needed)
        return true if respond_to?(:api_request?) && api_request?

        # Skip if global CSRF protection is disabled
        return true unless csrf_protection_enabled?

        false
      end

      # Check if request is a state-changing operation
      def state_changing_request?
        %w[POST PUT PATCH DELETE].include?(request.request_method)
      end

      private

      # Validate a CSRF token against the session
      #
      # This implements the same validation logic as Rack::Protection::AuthenticityToken
      # to ensure tokens from either source are accepted.
      #
      # @param sess [Hash] The session hash
      # @param token [String] The submitted token to validate
      # @return [Boolean] true if token is valid
      def valid_csrf_token?(sess, token)
        return false if token.nil? || !token.is_a?(String) || token.empty?

        begin
          decoded = Base64.urlsafe_decode64(token)
        rescue ArgumentError
          return false
        end

        real_token = decode_session_token(sess)
        return false unless real_token

        if decoded.length == TOKEN_LENGTH
          # Unmasked token - direct comparison
          secure_compare(decoded, real_token)
        elsif decoded.length == TOKEN_LENGTH * 2
          # Masked token - unmask then compare with global token
          unmasked = unmask_token(decoded)
          global   = global_token(real_token)
          secure_compare(unmasked, global) || secure_compare(unmasked, real_token)
        else
          false
        end
      end

      # Decode the raw token from session
      def decode_session_token(sess)
        raw = sess[SESSION_KEY]
        return nil unless raw

        Base64.urlsafe_decode64(raw)
      rescue ArgumentError
        nil
      end

      # Compute the global token (HMAC of real token)
      # This matches Rack::Protection::AuthenticityToken's global_token
      def global_token(real_token)
        OpenSSL::HMAC.digest(
          OpenSSL::Digest.new('SHA256'),
          real_token,
          '!real_csrf_token',
        )
      end

      # Unmask a masked token (XOR with one-time pad)
      def unmask_token(masked_token)
        token_length = masked_token.length / 2
        one_time_pad = masked_token[0...token_length]
        encrypted    = masked_token[token_length..]
        xor_byte_strings(one_time_pad, encrypted)
      end

      # XOR two byte strings
      def xor_byte_strings(s1, s2)
        s2 = s2.dup
        s1.bytesize.times { |i| s2.setbyte(i, s1.getbyte(i) ^ s2.getbyte(i)) }
        s2
      end

      # Constant-time string comparison to prevent timing attacks
      def secure_compare(a, b)
        return false unless a.bytesize == b.bytesize

        l                       = a.unpack('C*')
        r                       = 0
        b.each_byte { |byte| r |= byte ^ l.shift }
        r.zero?
      end

      # Check if CSRF protection is enabled in configuration
      def csrf_protection_enabled?
        return true unless defined?(OT) && OT.respond_to?(:conf)

        csrf_conf = OT.conf&.dig('site', 'security', 'csrf')
        return true unless csrf_conf

        csrf_conf['enabled'] != false
      end
    end
  end
end
