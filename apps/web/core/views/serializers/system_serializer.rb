# apps/web/core/views/serializers/system_serializer.rb

module Core
  module Views

    # Serializes system-level information for the frontend
    #
    # Responsible for transforming application version, runtime information,
    # and security-related values for frontend consumption.
    module SystemSerializer

      # Serializes system data from view variables
      #
      # @param view_vars [Hash] The view variables containing system information
      # @param i18n [Object] The internationalization instance
      # @return [Hash] Serialized system data including version and security values
      def self.serialize(view_vars, i18n)
        output = self.output_template

        output[:ot_version] = OT::VERSION.inspect
        output[:ruby_version] = if OT.sysinfo.nil?
          RUBY_VERSION.to_s
        else
           "#{OT.sysinfo.vm}-#{OT.sysinfo.ruby.join}"
        end

        output[:shrimp] = view_vars[:shrimp]
        output[:nonce] = view_vars[:nonce]
        output
      end

      class << self
        # Provides the base template for system serializer output
        #
        # @return [Hash] Template with all possible system output fields
        def output_template
          {
            ot_version: nil,
            ruby_version: nil,
            shrimp: nil,
            nonce: nil,
          }
        end
      end
      SerializerRegistry.register(self)
    end
  end
end
