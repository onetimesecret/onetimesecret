# apps/api/domains/logic/sender_config/base.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/mailer_config'
require_relative '../concerns/domain_config_authorization'

module DomainsAPI
  module Logic
    module SenderConfig
      # Base class for Domain Sender Configuration endpoints.
      #
      # Authorization model:
      #   1. Check custom_mail_enabled feature flag
      #   2. Load CustomDomain by domain_id (extid)
      #   3. Load Organization via domain.org_id
      #   4. Verify user is organization owner
      #   5. Verify organization has custom_mail_sender entitlement
      #
      class Base < DomainsAPI::Logic::Base
        include DomainsAPI::Logic::Concerns::DomainConfigAuthorization

        VERIFICATION_STATUS_PENDING = 'pending'

        attr_reader :custom_domain, :organization

        protected

        # Entitlement required for sender config operations.
        def config_entitlement
          'custom_mail_sender'
        end

        # Error message when custom_mail_sender entitlement is missing.
        def config_entitlement_error
          'Custom mail sender requires the custom_mail_sender entitlement. Please upgrade your plan.'
        end

        # Feature flag under features.organizations config.
        def config_feature_flag
          'custom_mail_enabled'
        end

        # Error message when feature flag is disabled.
        def config_feature_flag_error
          'Custom mail sender is not enabled on this instance'
        end

        # Full authorization check for domain sender config operations.
        # Loads domain and organization, verifies ownership and entitlement.
        #
        # @param domain_id [String] Domain extid
        # @return [void]
        def authorize_sender_config!(domain_id)
          authorize_domain_config!(domain_id)
        end

        # Enforce from_address domain restriction based on entitlement.
        #
        # Normalize from_address to use the custom domain's display_domain.
        #
        # Without the flexible_from_domain entitlement, the from_address is
        # always normalized to localpart@display_domain, preserving the local
        # part of the submitted address and defaulting to 'noreply' when blank.
        #
        # @param from_address [String] The submitted from_address
        # @param custom_domain [Onetime::CustomDomain] The custom domain record
        # @param organization [Onetime::Organization] The owning organization
        # @return [String] The normalized from_address
        def enforce_from_domain(from_address, custom_domain, organization)
          return from_address if organization.can?('flexible_from_domain')

          domain_part = custom_domain.display_domain.to_s
          return from_address if domain_part.empty?

          local_part = from_address.to_s.split('@', 2).first.to_s
          local_part = 'noreply' if local_part.empty?

          "#{local_part}@#{domain_part}"
        end
      end
    end
  end
end
