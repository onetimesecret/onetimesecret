# apps/api/domains/logic/homepage_config/base.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/homepage_config'
require_relative '../concerns/domain_config_authorization'

module DomainsAPI
  module Logic
    module HomepageConfig
      # Base class for Domain Homepage Configuration endpoints.
      #
      # Authorization model:
      #   1. Load CustomDomain by domain_id (extid)
      #   2. Load Organization via domain.org_id
      #   3. Verify user is organization owner
      #   4. Verify organization has homepage_secrets entitlement
      #
      class Base < DomainsAPI::Logic::Base
        include DomainsAPI::Logic::Concerns::DomainConfigAuthorization

        attr_reader :custom_domain, :organization

        protected

        # Entitlement required for homepage config operations.
        def config_entitlement
          'homepage_secrets'
        end

        # Error message when homepage_secrets entitlement is missing.
        def config_entitlement_error
          'Homepage secrets management requires the homepage_secrets entitlement. Please upgrade your plan.'
        end

        # Full authorization check for domain homepage config operations.
        # Loads domain and organization, verifies ownership and entitlement.
        #
        # @param domain_id [String] Domain extid
        # @return [void]
        def authorize_domain_homepage!(domain_id)
          authorize_domain_config!(domain_id)
        end
      end
    end
  end
end
