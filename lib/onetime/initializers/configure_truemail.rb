# lib/onetime/initializers/configure_truemail.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # ConfigureTruemail initializer
    #
    # Configures email validation via Truemail library. Reads configuration
    # from OT.conf['mail']['truemail'] and applies it to Truemail.configure.
    #
    # Runtime state set:
    # - Onetime::Runtime.email.truemail_configured
    #
    class ConfigureTruemail < Onetime::Boot::Initializer
      @provides = [:email_validation]

      def execute(_context)
        truemail_config = OT.conf['mail']['truemail']

        # Only configure if config exists
        if truemail_config.nil? || truemail_config.empty?
          OT.ld '[init] Truemail not configured (no config found)'
          Onetime::Runtime.email = Onetime::Runtime::Email.new(
            truemail_configured: false,
          )
          return
        end

        # Iterate over the keys in the mail/truemail config
        # and set the corresponding key in the Truemail config.
        Truemail.configure do |config|
          truemail_config.each do |key, value|
            actual_key = OT::Config.mapped_key(key)
            unless config.respond_to?("#{actual_key}=")
              OT.le "config.#{actual_key} does not exist"
              next
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

        # Set runtime state
        Onetime::Runtime.email = Onetime::Runtime::Email.new(
          truemail_configured: true,
        )

        OT.ld '[init] Truemail configured successfully'
      end
    end
  end
end
