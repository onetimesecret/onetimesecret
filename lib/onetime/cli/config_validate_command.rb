# lib/onetime/cli/config_validate_command.rb
#
# frozen_string_literal: true

require_relative '../operations/config/validate'

module Onetime
  module CLI
    # Validate the application config YAML against the Zod-derived JSON Schema.
    #
    # Mirrors `bin/ots billing catalog validate`. The schema is generated from
    # `src/schemas/contracts/config/config.ts` via
    # `pnpm run schemas:json:generate` and lives at
    # `generated/schemas/config/static.schema.json`.
    class ConfigValidateCommand < DelayBootCommand
      desc 'Validate config.defaults.yaml against the generated JSON Schema'

      option :config,
        type: :string,
        required: false,
        desc: 'Override path to the config YAML (default: etc/defaults/config.defaults.yaml)'

      option :schema,
        type: :string,
        required: false,
        desc: 'Override path to the JSON Schema (default: generated/schemas/config/static.schema.json)'

      def call(config: nil, schema: nil, **)
        result = Onetime::Operations::Config::Validate.call(
          config_path: config,
          schema_path: schema,
          progress: method(:show_progress),
        )

        puts

        unless result.success
          result.errors.each { |e| puts "Error: #{e}" }
          exit 1
        end

        if result.valid
          puts 'OK valid'
          exit 0
        end

        puts "Found #{result.errors.size} schema error#{'s' unless result.errors.size == 1}:"
        result.errors.each { |e| puts "  - #{e}" }
        exit 1
      end

      private

      def show_progress(message)
        puts message
      end
    end
  end
end

Onetime::CLI.register 'config validate', Onetime::CLI::ConfigValidateCommand
