# apps/web/core/views/serializers/system_serializer.rb

module Core
  module Views
    module SystemSerializer
      # - ot_version, ruby_version, shrimp
      def self.serialize(view_vars, i18n)
        output = self.output_template

        output[:ot_version] = OT::VERSION.inspect
        output[:ruby_version] = "#{OT.sysinfo.vm}-#{OT.sysinfo.ruby.join}"

        output[:shrimp] = view_vars[:shrimp]
        output
      end

      private

      def self.output_template
        {}
      end

    end
  end
end
