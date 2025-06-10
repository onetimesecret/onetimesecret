# lib/onetime/initializers/configure_truemail.rb

require 'onetime/refinements/hash_refinements'

module Onetime
  module Initializers
    module ConfigureTruemail

      using IndifferentHashAccess

      def self.run(options = {})
        truemail_config = OT.conf[:mail][:truemail]

        # Iterate over the keys in the mail/truemail config
        # and set the corresponding key in the Truemail config.
        Truemail.configure do |config|
          truemail_config.each do |key, value|
            actual_key = OT::Config::Utils.mapped_key(key)
            unless config.respond_to?("#{actual_key}=")
              OT.le "config.#{actual_key} does not exist"
              # next
            end
            OT.ld "Setting Truemail config key #{key} to #{value}"
            config.send("#{actual_key}=", value)
          end
        end

        OT.ld "[initializer] Truemail configured"
      end

    end
  end
end
