# apps/api/domains/logic/api_config/base.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/api_config'
require_relative '../concerns/domain_config_authorization'

module DomainsAPI
  module Logic
    module ApiConfig
      # Base class for Domain API Configuration endpoints.
      #
      # Authorization model:
      #   1. Load CustomDomain by domain_id (extid)
      #   2. Load Organization via domain.org_id
      #   3. Verify user is organization owner
      #   4. Verify organization has api_access entitlement
      #
      class Base < DomainsAPI::Logic::Base
        include DomainsAPI::Logic::Concerns::DomainConfigAuthorization

        attr_reader :custom_domain, :organization

        protected

        # Entitlement required for API config operations.
        def config_entitlement
          'api_access'
        end

        # Error message when api_access entitlement is missing.
        def config_entitlement_error
          'API configuration requires the api_access entitlement. Please upgrade your plan.'
        end

        # Full authorization check for domain API config operations.
        # Loads domain and organization, verifies ownership and entitlement.
        #
        # @param domain_id [String] Domain extid
        # @return [void]
        def authorize_domain_api!(domain_id)
          authorize_domain_config!(domain_id)
        end
      end
    end
  end
end
