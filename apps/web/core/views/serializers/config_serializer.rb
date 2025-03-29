# apps/web/core/views/serializers/config_serializer.rb

module Core
  module Views
    module ConfigSerializer
      # - secret_options, authentication
      # - regions_enabled, regions
      # - support_host, incoming_recipient
      def self.serialize(view_vars, i18n)

        # Add UI settings
        self[:jsvars][:ui] = jsvar(interface[:ui])

        self[:jsvars][:incoming_recipient] = jsvar(incoming_recipient)
        self[:jsvars][:support_host] = jsvar(support_host)
        self[:jsvars][:secret_options] = jsvar(secret_options)
        self[:jsvars][:frontend_host] = jsvar(frontend_host)

        self[:jsvars][:site_host] = jsvar(site[:host])

        # Only send the regions config when the feature is enabled.
        self[:jsvars][:regions_enabled] = jsvar(regions_enabled)
        self[:jsvars][:regions] = jsvar(regions) if regions_enabled
      end

      private

      def self.output_template
        {}
      end

    end
  end
end
