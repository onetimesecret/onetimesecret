# apps/web/core/views/serializers/config_serializer.rb

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
      # @param i18n [Object] The internationalization instance
      # @return [Hash] Serialized configuration data
      def self.serialize(view_vars, _i18n)
        output = output_template

        # NOTE: The keys available in view_vars are defined in initialize_view_vars
        site        = view_vars['site'] || {}
        development = view_vars['development']
        diagnostics = view_vars['diagnostics']

        output['ui']             = site.dig('interface', 'ui')
        output['authentication'] = site.fetch('authentication', nil)
        output['secret_options'] = site['secret_options']
        output['site_host']      = site['host']
        regions                  = site['regions'] || {}
        domains                  = site['domains'] || {}

        # Only send the regions config when the feature is enabled.
        output['regions_enabled'] = regions.fetch('enabled', false)
        output['regions']         = regions if output['regions_enabled']

        output['domains_enabled'] = domains.fetch('enabled', false)
        output['domains']         = domains if output['domains_enabled']

        # Link to the pricing page can be seen regardless of authentication status
        billing                   = OT.conf.fetch('billing', {})
        output['billing_enabled'] = billing.fetch('enabled', false)

        output['frontend_development'] = development['enabled'] || false
        output['frontend_host']        = development['frontend_host'] || ''

        sentry                = diagnostics.fetch('sentry', {})
        output['d9s_enabled'] = Onetime.d9s_enabled
        Onetime.with_diagnostics do
          output['diagnostics'] = {
            # e.g. {dsn: "https://...", ...}
            'sentry' => sentry.fetch('frontend', {}),
          }
        end

        # Feature flags for authentication methods
        # Only available in advanced mode (Rodauth)
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
            'diagnostics' => nil,
            'domains' => nil,
            'domains_enabled' => nil,
            'features' => nil,
            'frontend_development' => nil,
            'frontend_host' => nil,
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
        # based on the current authentication mode (basic vs advanced).
        #
        # @return [Hash] Feature flags for frontend consumption
        def build_feature_flags
          features = {
            'magic_links' => false,
            'email_auth' => false,
            'webauthn' => false,
          }

          # Passwordless features only available in advanced mode
          if Onetime.auth_config.advanced_enabled?
            # Check if email_auth is in the advanced features list
            advanced_features = Onetime.auth_config.advanced.fetch('features', [])
            features['magic_links'] = advanced_features.include?('email_auth')
            features['email_auth'] = advanced_features.include?('email_auth')
            features['webauthn'] = advanced_features.include?('webauthn')
          end

          features
        end
      end

      SerializerRegistry.register(self)
    end
  end
end
