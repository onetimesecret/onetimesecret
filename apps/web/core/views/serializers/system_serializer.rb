# apps/web/core/views/serializers/system_serializer.rb

module Core
  module Views
    module SystemSerializer
      # - ot_version, ruby_version
      def self.serialize(view_vars, i18n)
        self[:jsvars][:ot_version] = jsvar(OT::VERSION.inspect)
        self[:jsvars][:ruby_version] = jsvar("#{OT.sysinfo.vm}-#{OT.sysinfo.ruby.join}")

      end

      private

      def self.output_template
        {}
      end

    end
  end
end
