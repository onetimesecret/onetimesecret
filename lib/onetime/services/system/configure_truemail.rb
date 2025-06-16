# lib/onetime/services/system/configure_truemail.rb


module Onetime
  module Services
    module System

      def configure_truemail
        truemail_config = Onetime.conf&.dig(:mail, :truemail)

        # Iterate over the keys in the mail/truemail config
        # and set the corresponding key in the Truemail config.
        Truemail.configure do |config|
          truemail_config.each do |key, value|
            actual_key = OT::Configurator.mapped_key(key)
            unless config.respond_to?("#{actual_key}=")
              OT.le "config.#{actual_key} does not exist"
              # next
            end
            OT.ld "Setting Truemail config key #{key} to #{value}"
            config.send("#{actual_key}=", value)
          end
        end
      end

    end
  end
end
