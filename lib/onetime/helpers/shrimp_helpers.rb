# lib/onetime/helpers/shrimp_helpers.rb

require 'securerandom'

module Onetime
  module Helpers
    module ShrimpHelpers
      # Generate or retrieve the current CSRF token
      def shrimp_token
        session['shrimp'] ||= generate_shrimp
      end

      # Verify submitted CSRF token and regenerate if valid
      def verify_shrimp!(submitted_token)
        return true if skip_shrimp_check?

        stored_token = shrimp_token
        return false if stored_token.to_s.empty? || submitted_token.to_s.empty?

        # Use constant-time comparison to prevent timing attacks
        valid = Rack::Utils.secure_compare(stored_token.to_s, submitted_token.to_s)

        if valid
          regenerate_shrimp! # Prevent replay attacks
          OT.ld "[shrimp-success] Valid token for #{current_customer.custid}"
        else
          OT.ld "[shrimp-fail] Invalid token for #{current_customer.custid}"
          raise Onetime::FormError, "Security validation failed"
        end

        true
      end

      # Generate a new CSRF token
      def regenerate_shrimp!
        session['shrimp'] = generate_shrimp
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
        return true if api_request? && respond_to?(:api_request?)

        # Skip if global CSRF protection is disabled
        return true unless csrf_protection_enabled?

        false
      end

      # Check if request is a state-changing operation
      def state_changing_request?
        %w[POST PUT PATCH DELETE].include?(request.request_method)
      end

      private

      # Generate cryptographically secure CSRF token
      def generate_shrimp
        # 32 bytes = 256 bits of entropy
        SecureRandom.urlsafe_base64(32)
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
