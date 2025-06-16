# lib/onetime/services/system/configure_truemail.rb


module Onetime
  module Services
    module System

      def configure_truemail(config)
        validation_config = config['mail']['validation']['defaults']

        # NOTE: We need to convert string-like values to Symbols here in the mail
        # validation provider. Because we use redis as the backend and because
        # we use JSON schema validation and because we need common config conventions
        # between Ruby code and Typescript code, all keys are stored as strings and
        # all string-like values are stored as strings. The init scripts cannot
        # enforce Symbol types, so we handle that conversion here.
        if validation_config['default_validation_type']
          validation_config['default_validation_type'] = validation_config['default_validation_type'].to_sym
        end

        if validation_config['logger']['tracking_event']
          validation_config['logger']['tracking_event'] = validation_config['logger']['tracking_event'].to_sym
        end

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

    end
  end
end
