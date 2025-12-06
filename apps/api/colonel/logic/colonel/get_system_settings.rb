# apps/api/colonel/logic/colonel/get_system_settings.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      class GetSystemSettings < ColonelAPI::Logic::Base
        attr_reader :config_sections

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          @config_sections = {}
          site_config      = Onetime.conf['site'] || {}

          # Interface config (UI and API settings)
          @config_sections[:interface] = site_config['interface'] || {}

          # Secret options (TTL, passphrase, password generation)
          # These are under site.secret_options in the config
          @config_sections[:secret_options] = site_config['secret_options'] || {}

          # Authentication config (under site.authentication)
          @config_sections[:authentication] = site_config['authentication'] || {}

          # Emailer config (SMTP settings - top-level 'emailer' key)
          @config_sections[:emailer] = Onetime.conf['emailer'] || {}

          # Mail config (TrueMail validation - top-level 'mail' key)
          @config_sections[:mail] = Onetime.conf['mail'] || {}

          # Diagnostics (top-level 'diagnostics' key)
          # Include full diagnostics config, masking sensitive data
          diagnostics_config                          = Onetime.conf['diagnostics'] || {}
          @config_sections[:diagnostics]              = deep_copy(diagnostics_config)
          # Add redis URI with masked password for convenience
          @config_sections[:diagnostics]['redis_uri'] = Onetime.conf['redis']&.[]('uri')&.gsub(/:[^:@]*@/, ':****@')

          # Logging config (top-level 'logging' key)
          @config_sections[:logging] = Onetime.conf['logging'] || {}

          # Billing config (if enabled) - mask sensitive keys
          if Onetime.conf.key?('billing') && Onetime.conf['billing']&.[]('enabled')
            billing                           = deep_copy(Onetime.conf['billing'] || {})
            billing['stripe_key']             = mask_key(billing['stripe_key'])
            billing['webhook_signing_secret'] = '****' if billing['webhook_signing_secret']
            @config_sections[:billing]        = billing
          end

          # Features config (top-level 'features' key)
          @config_sections[:features] = Onetime.conf['features'] || {}

          success_data
        end

        private

        # Deep copy a frozen hash structure
        def deep_copy(obj)
          case obj
          when Hash
            obj.transform_values { |v| deep_copy(v) }
          when Array
            obj.map { |v| deep_copy(v) }
          else
            obj
          end
        end

        # Mask a key, keeping last 4 characters visible
        def mask_key(key)
          return nil if key.nil?
          return '****' if key.length <= 4

          ('*' * (key.length - 4)) + key[-4..]
        end

        def success_data
          {
            record: {},
            details: config_sections,
          }
        end
      end
    end
  end
end
