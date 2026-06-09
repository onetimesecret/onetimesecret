# apps/web/core/views/serializers/config_serializer.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/signin_config'
require 'onetime/models/custom_domain/sso_config'
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
    #   1. If request is from a custom domain with CustomDomain::SsoConfig -> tenant's provider
    #   2. If tenant has no config or is disabled -> platform fallback (if allowed)
    #   3. If fallback disallowed -> empty providers array
    #
    # Resolution Flow:
    #   view_vars['display_domain'] -> CustomDomain.load_by_display_domain -> CustomDomain::SsoConfig
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
        output['api']            = {
          'enabled' => site.dig('interface', 'api', 'enabled') != false,
          'guest_routes' => site.dig('interface', 'api', 'guest_routes') || {},
        }
        output['authentication'] = site.fetch('authentication', nil)
        output['homepage_mode']  = view_vars['homepage_mode']
        output['secret_options'] = site['secret_options']
        output['site_host']      = site['host']
        output['support_host']   = site.dig('support', 'host')
        regions                  = features.fetch('regions', {})
        domains                  = features.fetch('domains', {})

        # Only send the regions config when the feature is enabled.
        # Transform jurisdictions to send identifier + i18n key only (no domain data).
        output['regions_enabled'] = regions.fetch('enabled', false)
        output['regions']         = transform_regions(regions) if output['regions_enabled']

        output['domains_enabled'] = domains.fetch('enabled', false)
        output['domains']         = domains if output['domains_enabled']

        # Link to the pricing page can be seen regardless of authentication status
        output['billing_enabled'] = OT.billing_config.enabled?

        output['frontend_development'] = development['enabled'] || false
        output['frontend_host']        = development['frontend_host'] || ''

        # Branding config for frontend stores. Sourced from view_vars which
        # InitializeViewVars populates from OT.conf['brand'] with neutral
        # BrandSettingsConstants defaults per #3049.
        output['brand_primary_color']         = view_vars['brand_primary_color']
        output['brand_product_name']          = view_vars['brand_product_name']
        output['brand_product_domain']        = view_vars['brand_product_domain']
        output['brand_support_email']         = view_vars['brand_support_email']
        output['brand_corner_style']          = view_vars['brand_corner_style']
        output['brand_font_family']           = view_vars['brand_font_family']
        output['brand_button_text_light']     = view_vars['brand_button_text_light']
        output['brand_logo_url']              = view_vars['brand_logo_url']
        output['brand_favicon_url']           = view_vars['brand_favicon_url']
        output['brand_totp_issuer']           = view_vars['brand_totp_issuer']
        output['support_email']               = view_vars['support_email']
        output['docs_host']                   = view_vars['docs_host']

        # Pass development config to frontend (includes domain_context_enabled)
        output['development'] = {
          'enabled' => development['enabled'] || false,
          'domain_context_enabled' => development['domain_context_enabled'] || false,
        }

        sentry                = diagnostics.fetch('sentry', {})
        output['d9s_enabled'] = Onetime.d9s_enabled
        Onetime.with_diagnostics do
          defaults = sentry.fetch('defaults', {})
          frontend = sentry.fetch('frontend', {})

          output['diagnostics'] = {
            'sentry' => {
              'dsn' => frontend.fetch('dsn', ''),
              'trackComponents' => frontend.fetch('trackComponents', true),
              'sampleRate' => defaults.fetch('sampleRate', 1.0).to_f,
              'maxBreadcrumbs' => defaults.fetch('maxBreadcrumbs', 5).to_i,
              'logErrors' => defaults.fetch('logErrors', true),
              'environment' => OT.env,
              'release' => OT::VERSION.get_build_info,
            },
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
            'api' => nil,
            'authentication' => nil,
            'brand_primary_color' => nil,
            'brand_product_name' => nil,
            'brand_product_domain' => nil,
            'brand_support_email' => nil,
            'brand_corner_style' => nil,
            'brand_font_family' => nil,
            'brand_button_text_light' => nil,
            'brand_logo_url' => nil,
            'brand_favicon_url' => nil,
            'brand_totp_issuer' => nil,
            'd9s_enabled' => nil,
            'development' => nil,
            'diagnostics' => nil,
            'docs_host' => nil,
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
            'support_email' => nil,
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
          features = view_vars['features'] || {}

          {
            'lockout' => Onetime.auth_config.lockout_enabled?,
            'password_requirements' => Onetime.auth_config.password_requirements_enabled?,
            'active_sessions' => Onetime.auth_config.active_sessions_enabled?,
            'remember_me' => Onetime.auth_config.remember_me_enabled?,
            'mfa' => Onetime.auth_config.mfa_enabled?,
            'email_auth' => resolve_email_auth(view_vars),
            'webauthn' => Onetime.auth_config.webauthn_enabled?,
            'sso' => build_sso_config(view_vars),
            'restrict_to' => resolve_restrict_to(view_vars),
            'organizations' => {
              'enabled' => features.dig('organizations', 'enabled') || false,
              'sso_enabled' => features.dig('organizations', 'sso_enabled') || false,
              'custom_mail_enabled' => features.dig('organizations', 'custom_mail_enabled') || false,
              'incoming_secrets_enabled' => (features.dig('incoming', 'enabled') &&
                                              features.dig('organizations', 'incoming_secrets_enabled')) || false,
            },
          }
        end

        # Resolve restrict_to for the current request context.
        # Domain SigninConfig overrides global when enabled.
        def resolve_restrict_to(view_vars)
          domain_id = resolve_domain_id(view_vars)
          if domain_id
            signin_config = Onetime::CustomDomain::SigninConfig.find_by_domain_id(domain_id)
            return signin_config.restrict_to if signin_config&.enabled?
          end

          Onetime.auth_config.restrict_to
        end

        # Resolve email_auth availability for the current request context.
        #
        # AND semantics (differs from resolve_restrict_to's replace semantics):
        # a domain may DISABLE email_auth but cannot ENABLE it when the global
        # Rodauth route was never mounted. So the domain override only ever
        # narrows the global capability, never widens it.
        #
        # @param view_vars [Hash] View variables with request context
        # @return [Boolean] true if email_auth is available
        def resolve_email_auth(view_vars)
          global = Onetime.auth_config.email_auth_enabled?

          domain_id = resolve_domain_id(view_vars)
          if domain_id
            signin_config = Onetime::CustomDomain::SigninConfig.find_by_domain_id(domain_id)
            return global && signin_config.email_auth_enabled? if signin_config&.enabled?
          end

          global
        end

        # Build SSO configuration for frontend
        #
        # Returns domain-aware SSO provider configuration. For custom domains
        # with CustomDomain::SsoConfig, returns the tenant's provider. Otherwise returns
        # platform SSO configuration (from env vars).
        #
        # Resolution priority:
        #   1. CustomDomain::SsoConfig for tenant (if custom domain with domain SSO config)
        #   2. Platform SSO providers (from env vars, if fallback allowed)
        #   3. Disabled (empty providers)
        #
        # @param view_vars [Hash] View variables containing domain context
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
        # Looks up CustomDomain::SsoConfig (credentials) for the custom domain
        # and gates it on SigninConfig.sso_permitted_for? — the shared
        # activation authority. Tenant SSO config is returned only when the
        # credentials store is enabled AND the SigninConfig permits SSO. This
        # is the display half of the parity gate; the runtime half lives in
        # apps/web/auth/config/hooks/omniauth_tenant.rb and consults the same
        # predicate. SigninConfig.sso_enabled governs the TENANT's SSO only;
        # build_sso_config's platform-fallback policy is unchanged.
        #
        # @param view_vars [Hash] View variables
        # @return [Onetime::CustomDomain::SsoConfig, nil] Config if found and enabled
        def resolve_tenant_sso_config(view_vars)
          domain_id = resolve_domain_id(view_vars)
          return nil unless domain_id

          domain_config = Onetime::CustomDomain::SsoConfig.find_by_domain_id(domain_id)
          return nil unless domain_config&.enabled?
          return nil unless Onetime::CustomDomain::SigninConfig.sso_permitted_for?(domain_id)

          domain_config
        end

        # Resolve domain identifier from view variables
        #
        # @param view_vars [Hash] View variables
        # @return [String, nil] CustomDomain identifier (objid) or nil
        def resolve_domain_id(view_vars)
          display_domain = view_vars['display_domain']
          return nil if display_domain.to_s.empty?

          custom_domain = Onetime::CustomDomain.load_by_display_domain(display_domain)
          custom_domain&.identifier
        rescue Redis::BaseError => ex
          OT.le "[ConfigSerializer] Redis error resolving domain_id for domain=#{display_domain}: #{ex.class}"
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
        # When true, custom domains without CustomDomain::SsoConfig use platform SSO.
        # When false, such domains see no SSO buttons.
        #
        # @return [Boolean] true if fallback allowed (default: false)
        def allow_platform_fallback?
          Onetime.auth_config.allow_platform_fallback_for_tenants?
        end

        # Build SSO response for tenant configuration
        #
        # @param config [Onetime::CustomDomain::SsoConfig] Tenant SSO config
        # @return [Hash] SSO config hash for frontend
        def build_tenant_sso_response(config)
          {
            'enabled' => true,
            'enforce_sso_only' => config.enforce_sso_only?,
            'providers' => [
              {
                'route_name' => config.platform_route_name,
                'display_name' => config.display_name.to_s,
              },
            ],
          }
        end

        # Transform regions config for frontend consumption
        #
        # Passes through identifier, domain, icon, and i18n key.
        # Domain is public (users navigate to it directly).
        # Icons are optional; frontend falls back to src/sources/jurisdictions.ts.
        #
        # @param regions [Hash] Raw regions config from features
        # @return [Hash] Transformed regions with jurisdiction data
        def transform_regions(regions)
          jurisdictions = regions.fetch('jurisdictions', [])

          transformed_jurisdictions = jurisdictions.map do |j|
            identifier     = j['identifier'].to_s
            result         = {
              'identifier' => identifier,
              'domain' => j['domain'].to_s,
              'display_name_i18n_key' => j['display_name_i18n_key'] ||
                                         "web.regions.jurisdictions.#{identifier.downcase}.name",
            }
            result['icon'] = j['icon'] if j['icon'].is_a?(Hash)
            result
          end

          {
            'enabled' => regions.fetch('enabled', false),
            'current_jurisdiction' => regions['current_jurisdiction'],
            'jurisdictions' => transformed_jurisdictions,
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
