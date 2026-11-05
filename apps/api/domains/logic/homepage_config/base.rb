# apps/api/domains/logic/homepage_config/base.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/homepage_config'
require_relative '../../policies/domain_config_authorization'

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
        include DomainsAPI::Policies::DomainConfigAuthorization

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

        # Require the platform flag and the homepage_network_rules
        # entitlement for a request that changes stored network rules: a PUT
        # that changes a list, or a DELETE that would drop one.
        #
        # The flag (ORGS_HOMEPAGE_NETWORK_RULES_UI_ENABLED, default off) is the
        # install-wide switch, checked first so an install without it never
        # suggests an upgrade. Network rules are also a paid tier
        # (homepage_network_rules, Identity Plus) layered on homepage_secrets,
        # which the free plan carries.
        #
        # Freeze, don't drop, on downgrade or with the flag off: stored rules
        # keep being enforced (neither check runs on the anonymous paths, and
        # dropping them would widen access), while changing them, clearing
        # included, needs both back. The draft AccessConfig spec
        # (docs/specs/domain-ip-allowlist) takes the same position for its
        # allowlist. Call after #authorize_domain_homepage!, which loads
        # @organization.
        #
        # @param field [Symbol] :allowed_cidrs | :denied_cidrs, the list the
        #   refusal is tagged with
        # @return [void]
        def verify_network_rules_editable!(field)
          unless OT.conf.dig('features', 'organizations', 'homepage_network_rules_ui_enabled')
            raise_form_error(
              'Homepage network rules are not enabled on this installation',
              error_key: 'api.domains.errors.homepage_network_rules_disabled',
              field: field,
              error_type: :forbidden,
            )
          end
          return if @organization.can?('homepage_network_rules')

          raise_form_error(
            'Homepage network rules require the homepage_network_rules entitlement. Please upgrade your plan.',
            error_key: 'api.entitlements.errors.homepage_network_rules_required',
            field: field,
            error_type: :forbidden,
          )
        end
      end
    end
  end
end
