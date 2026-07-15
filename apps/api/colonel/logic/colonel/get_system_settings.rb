# apps/api/colonel/logic/colonel/get_system_settings.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # Get System Settings
      #
      # @api Returns the current system configuration organized by section:
      #   interface, secret options, authentication, emailer, mail, diagnostics,
      #   logging, billing, and features. Sensitive values such as API keys
      #   and webhook secrets are masked. Requires colonel role.
      class GetSystemSettings < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'systemSettings' }.freeze

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

          # Emailer config (SMTP settings - top-level 'emailer' key). Carries
          # user/pass — deep_copy then recursively mask credential-bearing keys
          # so no secret crosses the wire (host/port/region/from stay visible).
          @config_sections[:emailer] = mask_secrets(deep_copy(Onetime.conf['emailer'] || {}))

          # Mail config (TrueMail validation - top-level 'mail' key). Can carry a
          # verification-API key/token — mask the same way.
          @config_sections[:mail] = mask_secrets(deep_copy(Onetime.conf['mail'] || {}))

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

        # Keys whose VALUE is a credential and must be masked. Matches user,
        # pass(word), *secret*, *key*, *token*. Non-secret config (host, port,
        # region, from, from_name, domain, tls, mode) stays visible.
        SECRET_KEY_PATTERN = /user|pass|secret|key|token|password/i
        private_constant :SECRET_KEY_PATTERN

        # Recursively mask every credential-bearing string value in a (already
        # deep-copied) config section, keying off the FIELD NAME. Non-string
        # values under a secret key (e.g. a nested hash) are recursed into.
        def mask_secrets(obj)
          case obj
          when Hash
            obj.each_with_object({}) do |(k, v), acc|
              acc[k] = if k.to_s.match?(SECRET_KEY_PATTERN) && v.is_a?(String)
                         mask_key(v)
                       else
                         mask_secrets(v)
                       end
            end
          when Array
            obj.map { |v| mask_secrets(v) }
          else
            obj
          end
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
