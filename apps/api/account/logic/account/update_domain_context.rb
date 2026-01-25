# apps/api/account/logic/account/update_domain_context.rb
#
# frozen_string_literal: true

module AccountAPI::Logic
  module Account
    # Updates the user's domain context preference in their session
    #
    # Domain context determines which domain context the user operates in.
    # This is stored in the session so it persists across page refreshes,
    # new tabs, and browser restarts.
    #
    # The domain must be either:
    # - The canonical domain (e.g., "onetimesecret.com")
    # - One of the user's custom domains from their organizations
    #
    # Anonymous users can only use the canonical domain.
    class UpdateDomainContext < UpdateAccountField
      include Onetime::LoggerMethods

      attr_reader :new_domain_context, :old_domain_context

      def process_params
        domain_param         = params['domain']
        @new_domain_context  = normalize_domain(domain_param)
        @old_domain_context  = sess&.[]('domain_context')
      end

      # Maximum domain length per RFC 1035 (253 chars total, 63 per label)
      MAX_DOMAIN_LENGTH   = 253
      # Allowed characters in domain names per RFC 1123
      DOMAIN_CHAR_PATTERN = /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\z/

      def normalize_domain(value)
        return nil if value.nil?

        normalized = value.to_s.strip.downcase

        # Basic length validation to prevent malformed session data
        return nil if normalized.empty? || normalized.length > MAX_DOMAIN_LENGTH

        # Character validation: only allow valid domain characters
        return nil unless normalized.match?(DOMAIN_CHAR_PATTERN)

        normalized
      end

      def raise_concerns
        # Require authentication - anonymous users cannot set domain context
        raise OT::Unauthorized, 'Authentication required' if cust.anonymous?

        field_specific_concerns
      end

      def success_data
        {
          domain_context: new_domain_context,
          previous_domain_context: old_domain_context,
        }
      end

      private

      def field_name
        :domain_context
      end

      def field_specific_concerns
        raise_form_error 'Domain is required' if new_domain_context.nil? || new_domain_context.empty?
        raise_form_error 'Invalid domain' unless valid_domain?(new_domain_context)
      end

      def valid_update?
        valid_domain?(new_domain_context)
      end

      def perform_update
        app_logger.debug 'Updating domain context in session',
          {
            old_domain_context: old_domain_context,
            new_domain_context: new_domain_context,
            customer_id: cust.extid,
          }

        sess['domain_context'] = new_domain_context
      end

      # Validates that the domain is either the canonical domain or
      # one of the user's custom domains
      #
      # @param domain [String] The domain to validate
      # @return [Boolean] true if domain is valid for this user
      def valid_domain?(domain)
        return false if domain.nil? || domain.empty?

        # Allow canonical domain
        canonical = Onetime::Middleware::DomainStrategy.canonical_domain
        return true if domain == canonical

        # Check if domain is in user's custom domains list
        return false unless domains_enabled

        custom_domains = cust.custom_domains_list.map(&:display_domain)
        custom_domains.include?(domain)
      end

      def log_update
        app_logger.info 'Domain context updated',
          {
            customer_id: cust.extid,
            session_id: session_sid,
            old_domain_context: old_domain_context,
            new_domain_context: new_domain_context,
          }
      end
    end
  end
end
