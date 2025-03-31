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
      def self.serialize(view_vars, i18n)
        output = self.output_template

        site = view_vars[:site] || {}
        incoming = view_vars[:incoming] # TODO: Update to features.incoming
        development = view_vars[:development]
        diagnostics = view_vars[:diagnostics]

        output[:ui] = site.dig(:interface, :ui)
        output[:authentication] = site.fetch(:authentication, nil)
        output[:support_host] = site.dig(:support, :host)
        output[:secret_options] = site[:secret_options]
        output[:site_host] = site[:host]
        regions = site[:regions] || {}
        domains = site[:domains] || {}

        # Only send the regions config when the feature is enabled.
        output[:regions_enabled] = regions.fetch(:enabled, false)
        output[:regions] = regions if output[:regions_enabled]

        output[:domains_enabled] = domains.fetch(:enabled, false)
        output[:domains] = domains if output[:domains_enabled]

        output[:incoming_recipient] = incoming.fetch(:email, nil)

        # Link to the pricing page can be seen regardless of authentication status
        output[:plans_enabled] = site.dig(:plans, :enabled) || false

        output[:frontend_development] = development[:enabled] || false
        output[:frontend_host] = development[:frontend_host] || ''

        sentry = diagnostics.fetch(:sentry, {})
        output[:d9s_enabled] = Onetime.d9s_enabled
        Onetime.with_diagnostics do
          output[:diagnostics] = {
            # e.g. {dsn: "https://...", ...}
            sentry: sentry.fetch(:frontend, {}),
          }
        end

        output
      end

      class << self
        private

        # Provides the base template for configuration serializer output
        #
        # @return [Hash] Template with all possible configuration output fields
        def output_template
          {
            authentication: nil,
            d9s_enabled: nil,
            diagnostics: nil,
            domains: nil,
            domains_enabled: nil,
            frontend_development: nil,
            frontend_host: nil,
            incoming_recipient: nil,
            plans_enabled: nil,
            regions: nil,
            regions_enabled: nil,
            secret_options: nil,
            site_host: nil,
            support_host: nil,
            ui: nil,
          }
        end
      end

      SerializerRegistry.register(self)
    end
  end
end
