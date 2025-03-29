# apps/web/core/views/serializers/diagnostics_serializer.rb

module Core
  module Views
    module DiagnosticsSerializer
      # - d9s_enabled, diagnostics, messages, global_banner
      def self.serialize(view_vars, i18n)
        # Diagnostics
        sentry = OT.conf.dig(:diagnostics, :sentry) || {}
        self[:jsvars][:d9s_enabled] = jsvar(OT.d9s_enabled) # pass global flag
        Onetime.with_diagnostics do
          config = sentry.fetch(:frontend, {})
          self[:jsvars][:diagnostics] = {
            # e.g. {dsn: "https://...", ...}
            sentry: jsvar(config)
          }
        end
      end

      private

      def self.output_template
        {}
      end

    end
  end
end
