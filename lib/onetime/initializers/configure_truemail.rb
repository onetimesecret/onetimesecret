# lib/onetime/initializers/configure_truemail.rb

module Onetime
  module Initializers

    def configure_truemail
      truemail_config = Onetime.conf[:mail][:truemail]

      # Iterate over the keys in the mail/truemail config
      # and set the corresponding key in the Truemail config.
      # Note: IndifferentHash yields string keys during iteration, so we
      # convert to symbol for KEY_MAP lookup and Truemail config methods.
      Truemail.configure do |config|
        truemail_config.each do |key, value|
          sym_key = key.to_sym
          actual_key = OT::Config.mapped_key(sym_key)
          unless config.respond_to?("#{actual_key}=")
            OT.le "config.#{actual_key} does not exist"
            # next
          end
          OT.ld "Setting Truemail config key #{sym_key} to #{value}"
          config.send("#{actual_key}=", value)
        end
      end

    end
  end
end
