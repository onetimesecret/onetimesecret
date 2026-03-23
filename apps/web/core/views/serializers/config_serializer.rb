# apps/web/core/views/serializers/config_serializer.rb
#
# frozen_string_literal: true

require 'onetime/models/org_sso_config'
require 'onetime/models/custom_domain'

module Core
  module Views
    # Serializes application configuration for the frontend
    #
    # Responsible for transforming server-side configuration settings into
    # a consistent format that can be safely exposed to the frontend.
    #
    # SSO Provider Resolution:
    # The serializer returns domain-aware SSO providers based on request context:
    #   1. If request is from a custom domain with OrgSsoConfig -> tenant's provider
    #   2. If tenant has no config or is disabled -> platform fallback (if allowed)
    #   3. If fallback disallowed -> empty providers array
    #
    # Resolution Flow:
    #   view_vars['organization'] -> org_id -> OrgSsoConfig.find_by_org_id
    #   OR
    #   view_vars['display_domain'] -> CustomDomain.load_by_display_domain -> org_id
    #
    module ConfigSerializer
      # Serializes configuration data from view variables
      #
      # Transforms server configuration including site settings, feature flags,
      # and environment variables into frontend-safe configuration.
      #
      # @param view_vars [Hash] The view variables containing site configuration
      # @return [Hash] Serialized configuration data
      def self.serialize(view_vars)
        output = output_template

        # NOTE: The keys available in view_vars are defined in initialize_view_vars
        site        = view_vars['site'] || {}
        features    = view_vars['features'] || {}
        development = view_vars['development']
        diagnostics = view_vars['diagnostics']

        output['ui']             = site.dig('interface', 'ui')
        output['authentication'] = site.fetch('authentication', nil)
        output['homepage_mode']  = view_vars['homepage_mode']
        output['secret_options'] = site['secret_options']
        output['site_host']      = site['host']
        output['support_host']   = site.dig('support', 'host')
        regions                  = features.fetch('regions', {})
        domains                  = features.fetch('domains', {})

        # Only send the regions config when the feature is enabled.
        output['regions_enabled'] = regions.fetch('enabled', false)
        output['regions']         = regions if output['regions_enabled']

        output['domains_enabled'] = domains.fetch('enabled', false)
        output['domains']         = domains if output['domains_enabled']

        # Link to the pricing page can be seen regardless of authentication status
        output['billing_enabled'] = OT.billing_config.enabled?

        output['frontend_development'] = development['enabled'] || false
        output['frontend_host']        = development['frontend_host'] || ''

        # Pass development config to frontend (includes domain_context_enabled)
        output['development'] = {
          'enabled' => development['enabled'] || false,
          'domain_context_enabled' => development['domain_context_enabled'] || false,
        }

        sentry                = diagnostics.fetch('sentry', {})
        output['d9s_enabled'] = Onetime.d9s_enabled
        Onetime.with_diagnostics do
          output['diagnostics'] = {
            # e.g. {dsn: "https://...", ...}
            'sentry' => sentry.fetch('frontend', {}),
          }
        end

        # Feature flags for authentication methods
        # Only available in full mode (Rodauth)
        output['features'] = build_feature_flags(view_vars)

        output
      end

      class << self
        # Provides the base template for configuration serializer output
        #
        # @return [Hash] Template with all possible configuration output fields
        def output_template
          {
            'authentication' => nil,
            'd9s_enabled' => nil,
            'development' => nil,
            'diagnostics' => nil,
            'domains' => nil,
            'domains_enabled' => nil,
            'features' => nil,
            'frontend_development' => nil,
            'frontend_host' => nil,
            'homepage_mode' => nil,
            'billing_enabled' => nil,
            'regions' => nil,
            'regions_enabled' => nil,
            'secret_options' => nil,
            'site_host' => nil,
            'support_host' => nil,
            'ui' => nil,
          }
        end

        # Build feature flags for authentication methods
        #
        # Feature flags indicate which authentication methods are available
        # based on the current authentication mode (simple vs full).
        # Uses AuthConfig methods which already check full_enabled? internally.
        #
        # @param view_vars [Hash] View variables with request context
        # @return [Hash] Feature flags for frontend consumption
        def build_feature_flags(view_vars)
          {
            'lockout' => Onetime.auth_config.lockout_enabled?,
            'password_requirements' => Onetime.auth_config.password_requirements_enabled?,
            'active_sessions' => Onetime.auth_config.active_sessions_enabled?,
            'remember_me' => Onetime.auth_config.remember_me_enabled?,
            'mfa' => Onetime.auth_config.mfa_enabled?,
            'email_auth' => Onetime.auth_config.email_auth_enabled?,
            'webauthn' => Onetime.auth_config.webauthn_enabled?,
            'sso' => build_sso_config(view_vars),
            'sso_only' => Onetime.auth_config.sso_only_enabled?,
          }
        end

        # Build SSO configuration for frontend
        #
        # Returns domain-aware SSO provider configuration. For custom domains
        # with OrgSsoConfig, returns the tenant's provider. Otherwise returns
        # platform SSO configuration (from env vars).
        #
        # Resolution priority:
        #   1. OrgSsoConfig for tenant (if custom domain with org SSO config)
        #   2. Platform SSO providers (from env vars, if fallback allowed)
        #   3. Disabled (empty providers)
        #
        # @param view_vars [Hash] View variables containing organization context
        # @return [Boolean, Hash] false if disabled, otherwise config hash
        def build_sso_config(view_vars)
          # Try tenant-specific SSO config first
          tenant_config = resolve_tenant_sso_config(view_vars)

          if tenant_config
            return build_tenant_sso_response(tenant_config)
          end

          # Check if we're on a custom domain that should have tenant config
          # but doesn't - honor the fallback policy
          if tenant_domain?(view_vars) && !allow_platform_fallback?
            return { 'enabled' => false, 'providers' => [] }
          end

          # Fall back to platform SSO config (from env vars)
          build_platform_sso_config
        end

        # Resolve tenant SSO configuration from request context
        #
        # Attempts to find OrgSsoConfig using:
        #   1. Organization from view_vars (already resolved by auth strategy)
        #   2. CustomDomain lookup from display_domain
        #
        # @param view_vars [Hash] View variables
        # @return [Onetime::OrgSsoConfig, nil] Tenant config if found and enabled
        def resolve_tenant_sso_config(view_vars)
          org_id = resolve_org_id(view_vars)
          return nil unless org_id

          config = Onetime::OrgSsoConfig.find_by_org_id(org_id)
          return nil unless config&.enabled?

          config
        end

        # Resolve organization ID from view variables
        #
        # @param view_vars [Hash] View variables
        # @return [String, nil] Organization objid or nil
        def resolve_org_id(view_vars)
          # First try the pre-resolved organization from auth strategy
          organization = view_vars['organization']
          return organization.objid if organization

          # Fall back to CustomDomain lookup from display_domain
          display_domain = view_vars['display_domain']
          return nil if display_domain.to_s.empty?

          custom_domain = Onetime::CustomDomain.load_by_display_domain(display_domain)
          custom_domain&.org_id
        rescue Redis::BaseError
          # Log but don't fail - fall back to platform config
          nil
        end

        # Check if request is from a tenant/custom domain
        #
        # @param view_vars [Hash] View variables
        # @return [Boolean] true if on a custom domain
        def tenant_domain?(view_vars)
          strategy = view_vars['domain_strategy']
          strategy == :custom
        end

        # Check if platform fallback is allowed for tenant domains
        #
        # When true, custom domains without OrgSsoConfig use platform SSO.
        # When false, such domains see no SSO buttons.
        #
        # @return [Boolean] true if fallback allowed (default: true)
        def allow_platform_fallback?
          setting = OT.conf.dig('site', 'sso', 'allow_platform_fallback_for_tenants')
          # Default to true for backward compatibility
          setting.nil? || setting
        end

        # Build SSO response for tenant configuration
        #
        # @param config [Onetime::OrgSsoConfig] Tenant SSO config
        # @return [Hash] SSO config hash for frontend
        def build_tenant_sso_response(config)
          {
            'enabled' => true,
            'providers' => [
              {
                'route_name' => config.provider_type.to_s,
                'display_name' => config.display_name.to_s,
              },
            ],
          }
        end

        # Build platform SSO configuration from environment variables
        #
        # This is the original behavior - reading SSO providers from
        # AuthConfig which derives them from environment variables.
        #
        # @return [Boolean, Hash] false if disabled, otherwise config hash
        def build_platform_sso_config
          return false unless Onetime.auth_config.sso_enabled?

          providers = Onetime.auth_config.sso_providers

          {
            'enabled' => true,
            'providers' => providers.map do |p|
              {
                'route_name' => p['route_name'].to_s,
                'display_name' => p['display_name'].to_s,
              }
            end,
          }
        end
      end

      SerializerRegistry.register(self)
    end
  end
end
