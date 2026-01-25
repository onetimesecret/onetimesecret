# apps/web/core/views/serializers/config_serializer.rb
#
# frozen_string_literal: true

module Core
  module Views
    # Serializes application configuration for the frontend
    #
    # Responsible for transforming server-side configuration settings into
    # a consistent format that can be safely exposed to the frontend.
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
        output['features'] = build_feature_flags

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
            'ui' => nil,
          }
        end

        # Build feature flags for authentication methods
        #
        # Feature flags indicate which authentication methods are available
        # based on the current authentication mode (simple vs full).
        # Uses AuthConfig methods which already check full_enabled? internally.
        #
        # @return [Hash] Feature flags for frontend consumption
        def build_feature_flags
          {
            'hardening' => Onetime.auth_config.hardening_enabled?,
            'active_sessions' => Onetime.auth_config.active_sessions_enabled?,
            'remember_me' => Onetime.auth_config.remember_me_enabled?,
            'mfa' => Onetime.auth_config.mfa_enabled?,
            'email_auth' => Onetime.auth_config.email_auth_enabled?,
            'webauthn' => Onetime.auth_config.webauthn_enabled?,
            'omniauth' => build_omniauth_config,
          }
        end

        # Build OmniAuth configuration for frontend
        #
        # Returns false if disabled, or a hash with enabled status and
        # optional provider name for display customization.
        #
        # @return [Boolean, Hash] false if disabled, otherwise config hash
        def build_omniauth_config
          return false unless Onetime.auth_config.omniauth_enabled?

          config                  = { 'enabled' => true }
          provider_name           = Onetime.auth_config.omniauth_provider_name
          config['provider_name'] = provider_name if provider_name
          config['route_name']    = Onetime.auth_config.omniauth_route_name
          config
        end
      end

      SerializerRegistry.register(self)
    end
  end
end
