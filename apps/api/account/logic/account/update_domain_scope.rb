# apps/api/account/logic/account/update_domain_scope.rb
#
# frozen_string_literal: true

module AccountAPI::Logic
  module Account
    # Updates the user's domain scope preference in their session
    #
    # Domain scope determines which domain context the user operates in.
    # This is stored in the session so it persists across page refreshes,
    # new tabs, and browser restarts.
    #
    # The domain must be either:
    # - The canonical domain (e.g., "onetimesecret.com")
    # - One of the user's custom domains from their organizations
    #
    # Anonymous users can only use the canonical domain.
    class UpdateDomainScope < UpdateAccountField
      include Onetime::LoggerMethods

      attr_reader :new_domain_scope, :old_domain_scope

      def process_params
        domain_param      = params['domain']
        @new_domain_scope = normalize_domain(domain_param)
        @old_domain_scope = sess&.[]('domain_scope')
      end

      def normalize_domain(value)
        return nil if value.nil?

        value.to_s.strip.downcase
      end

      def raise_concerns
        # Require authentication - anonymous users cannot set domain scope
        raise OT::Unauthorized, 'Authentication required' if cust.anonymous?

        field_specific_concerns
      end

      def success_data
        {
          domain_scope: new_domain_scope,
          previous_domain_scope: old_domain_scope,
        }
      end

      private

      def field_name
        :domain_scope
      end

      def field_specific_concerns
        raise_form_error 'Domain is required' if new_domain_scope.nil? || new_domain_scope.empty?
        raise_form_error 'Invalid domain' unless valid_domain?(new_domain_scope)
      end

      def valid_update?
        valid_domain?(new_domain_scope)
      end

      def perform_update
        app_logger.debug 'Updating domain scope in session',
          {
            old_domain_scope: old_domain_scope,
            new_domain_scope: new_domain_scope,
            customer_id: cust.custid,
          }

        sess['domain_scope'] = new_domain_scope
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
        app_logger.info 'Domain scope updated',
          {
            customer_id: cust.custid,
            session_id: session_sid,
            old_domain_scope: old_domain_scope,
            new_domain_scope: new_domain_scope,
          }
      end
    end
  end
end
