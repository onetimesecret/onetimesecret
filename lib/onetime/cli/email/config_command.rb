# lib/onetime/cli/email/config_command.rb
#
# frozen_string_literal: true

# CLI command for displaying current email delivery configuration.
#
# Usage:
#   ots email config              # Show config in text format
#   ots email config --format json

require 'json'

module Onetime
  module CLI
    module Email
      class ConfigCommand < Command
        desc 'Show current email delivery configuration'

        option :format,
          type: :string,
          default: 'text',
          aliases: ['f'],
          desc: 'Output format: text or json'

        def call(format: 'text', **)
          boot_application!

          config   = build_config_summary
          provider = config[:provider]

          if format == 'json'
            puts JSON.pretty_generate(config)
          else
            output_text(config, provider)
          end
        end

        private

        def build_config_summary
          provider       = Onetime::Mail::Mailer.send(:determine_provider)
          raw_config     = Onetime::Mail::Mailer.send(:emailer_config)
          explicit_mode  = raw_config['mode']&.to_s&.downcase
          auto_detected  = explicit_mode.nil? || explicit_mode.empty?

          summary = {
            provider: provider,
            auto_detected: auto_detected,
            from_address: Onetime::Mail::Mailer.from_address,
            from_name: Onetime::Mail::Mailer.from_name,
          }

          summary[:provider_config] = masked_provider_config(provider, raw_config)
          summary
        end

        def masked_provider_config(provider, raw_config)
          case provider
          when 'smtp'
            {
              host: raw_config['host'] || ENV.fetch('SMTP_HOST', nil),
              port: raw_config['port'] || ENV.fetch('SMTP_PORT', nil),
              domain: raw_config['domain'] || ENV.fetch('SMTP_DOMAIN', nil),
              tls: raw_config['tls'],
              has_credentials: smtp_credentials?(raw_config),
            }
          when 'ses'
            {
              region: raw_config['region'] || ENV.fetch('AWS_REGION', nil),
              has_credentials: ses_credentials?(raw_config),
            }
          when 'sendgrid'
            {
              has_api_key: sendgrid_key?(raw_config),
            }
          else
            {}
          end
        end

        def smtp_credentials?(conf)
          user = conf['user'] || ENV.fetch('SMTP_USERNAME', nil)
          pass = conf['pass'] || ENV.fetch('SMTP_PASSWORD', nil)
          !(user.nil? || user.empty?) && !(pass.nil? || pass.empty?)
        end

        def ses_credentials?(conf)
          key    = conf['user'] || ENV.fetch('AWS_ACCESS_KEY_ID', nil)
          secret = conf['pass'] || ENV.fetch('AWS_SECRET_ACCESS_KEY', nil)
          !(key.nil? || key.empty?) && !(secret.nil? || secret.empty?)
        end

        def sendgrid_key?(conf)
          key = conf['sendgrid_api_key'] || conf['pass'] || ENV.fetch('SENDGRID_API_KEY', nil)
          !(key.nil? || key.empty?)
        end

        def output_text(config, provider)
          puts format('Provider:       %s%s', provider, config[:auto_detected] ? ' (auto-detected)' : '')
          puts format('From address:   %s', config[:from_address])
          puts format('From name:      %s', config[:from_name] || '(not set)')
          puts

          pc = config[:provider_config]
          return if pc.nil? || pc.empty?

          puts "#{provider.upcase} settings:"
          pc.each do |key, value|
            label   = key.to_s.tr('_', ' ').capitalize
            display = value.nil? ? '(not set)' : value.to_s
            puts format('  %-18s %s', "#{label}:", display)
          end
        end
      end
    end

    register 'email config', Email::ConfigCommand
  end
end
