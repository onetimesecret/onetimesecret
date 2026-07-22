# lib/onetime/initializers/check_tenant_sso_trust.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # CheckTenantSsoTrust initializer
    #
    # Guards the #3836 email-linking escape hatch against the multi-tenant
    # surface. The SSO email-linking trust flag
    # (SSO_TRUST_EMAIL_FOR_LINKING / per-provider *_TRUST_EMAIL_FOR_LINKING)
    # lets an SSO identity auto-link to an account LOCATED purely by email —
    # the ONE sanctioned exception to "email may LOCATE, only a credential may
    # BIND". It is safe ONLY when the operator controls both OTS and the IdP
    # (self-hosted single-tenant).
    #
    # By construction the flag applies only to the platform (env-configured)
    # provider path; the tenant callback path (OmniAuthTenant, gated on
    # session[:validated_omniauth_domain_id]) ignores it. So on a deployment
    # that ALSO has tenant SsoConfig(s), the flag is a footgun: an operator
    # may believe they enabled cross-IdP email linking for tenants when they
    # have not.
    #
    # This guard WARNS (non-fatal) when the flag is on AND at least one tenant
    # SsoConfig exists. It never raises: production has live tenant SsoConfigs
    # plus ~200k accounts, and a fatal guard would brick those deploys. A clean
    # install (flag off) boots silently.
    #
    # Refs: #3840 (Phase 1), #3836
    class CheckTenantSsoTrust < Onetime::Boot::Initializer
      @depends_on = [:database]
      @optional   = true

      def execute(_context)
        # Only speak up when the operator actually turned the flag on. A clean
        # install with the flag off must boot silently.
        return unless Onetime.auth_config.trust_email_for_linking_enabled?

        # Model may be absent in stripped/degraded boots — nothing to check.
        return unless defined?(Onetime::CustomDomain::SsoConfig)

        # O(1) ZCARD on the instances sorted set. NEVER load every SsoConfig
        # (`.all.any?`) — this runs on the boot path of a ~200k-account deploy.
        return unless Onetime::CustomDomain::SsoConfig.count.positive?

        auth_logger.warn(
          '[check_tenant_sso_trust] SSO email-linking trust flag is ENABLED ' \
          '(SSO_TRUST_EMAIL_FOR_LINKING / per-provider *_TRUST_EMAIL_FOR_LINKING) ' \
          'while tenant CustomDomain::SsoConfig record(s) exist. This flag is ' \
          'UNSAFE on the multi-tenant surface and is IGNORED there by ' \
          'construction: it applies only to the platform (env-configured) SSO ' \
          'provider path, never to per-domain tenant SSO callbacks. If you meant ' \
          'to enable email-based linking for tenants, this flag does NOT do that. ' \
          'It is intended for self-hosted single-tenant deployments where the ' \
          'operator controls both OTS and the IdP (#3836).',
        )
      end
    end
  end
end
