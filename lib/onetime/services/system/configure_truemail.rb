# lib/onetime/services/system/configure_truemail.rb

module Onetime
  module Services
    module System
      def configure_truemail(config)
        # The static config arrives frozen in time so we need to make our
        # own copy of it so we can modify it here locally.
        validation_config = OT::Utils.deep_clone(
          config['mail']['validation']['defaults'],
        )

        # NOTE: We need to convert string-like values to Symbols here in the mail
        # validation provider. Because we use redis as the backend and because
        # we use JSON schema validation and because we need common config
        # conventions between Ruby code and Typescript code, all keys are stored
        # as strings and all string-like values are stored as strings. The init
        # scripts cannot enforce Symbol types, so we handle that conversion here.
        convert_validation_type_to_symbol(validation_config)
        convert_tracking_event_to_symbol(validation_config)

        # Iterate over the keys in the mail/truemail config
        # and set the corresponding key in the Truemail config.
        Truemail.configure do |conf|
          validation_config.each do |key, value|
            actual_key = OT::Configurator::Utils.mapped_key(key)
            unless conf.respond_to?("#{actual_key}=")
              OT.le "conf.#{actual_key} does not exist"
              # next
            end
            OT.ld "Setting Truemail config key #{key} to #{value}"
            conf.send("#{actual_key}=", value)
          end
        end
      end

      private

      def convert_validation_type_to_symbol(conf)
        default_type = conf['default_validation_type']
        return unless default_type

        conf['default_validation_type'] = default_type.to_sym
      end

      def convert_tracking_event_to_symbol(conf)
        tracking_event = conf.dig('logger', 'tracking_event')
        return unless tracking_event

        conf['logger']['tracking_event'] = tracking_event.to_sym
      end
    end
  end
end
