# lib/onetime/initializers/configure_truemail.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    def configure_truemail
      truemail_config = Onetime.conf['mail']['truemail']

      # Iterate over the keys in the mail/truemail config
      # and set the corresponding key in the Truemail config.
      Truemail.configure do |config|
        truemail_config.each do |key, value|
          actual_key = OT::Config.mapped_key(key)
          unless config.respond_to?("#{actual_key}=")
            OT.le "config.#{actual_key} does not exist"
          end

          # Convert validation type strings to symbols
          # YAML parses `default_validation_type: regex` as string, but Truemail expects symbol
          if key == 'default_validation_type' && value.is_a?(String)
            value = value.to_sym
          end

          # Convert validation_type_for hash values from strings to symbols
          # YAML parses `example.com: regex` as {string => string}, but Truemail expects {string => symbol}
          if key == 'validation_type_for' && value.is_a?(Hash)
            value = value.transform_values(&:to_sym)
          end

          # OT.ld "[init] Truemail #{key} to #{value}"
          config.send("#{actual_key}=", value)
        end
      end
    end
  end
end
