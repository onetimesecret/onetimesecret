# lib/onetime/cli/email/config_command.rb
#
# frozen_string_literal: true

# CLI command for displaying current email delivery configuration.
#
# Usage:
#   ots email config              # Show config in text format
#   ots email config --format json

require 'json'
require 'onetime/operations/email/config_summary'

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

          # Delegate to the single shared summary (also used by the colonel
          # GET /api/colonel/email/config endpoint) so the two never drift.
          config   = Onetime::Operations::Email::ConfigSummary.build
          provider = config[:provider]

          if format == 'json'
            puts JSON.pretty_generate(config)
          else
            output_text(config, provider)
          end
        end

        private

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
