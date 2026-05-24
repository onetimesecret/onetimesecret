# lib/onetime/cli/config_group_command.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    # Top-level `bin/ots config` group; lists available subcommands.
    class ConfigGroupCommand < DelayBootCommand
      desc 'Manage and validate application configuration'

      def call(**)
        puts <<~HELP
          Config Management Commands:

            bin/ots config validate    Validate config.defaults.yaml against
                                       the Zod-derived JSON Schema
                                       (generated/schemas/config/static.schema.json)

          Examples:
            bin/ots config validate
            bin/ots config validate --config /path/to/config.yaml
            bin/ots config validate --schema /path/to/schema.json

          The JSON Schema is regenerated from
          `src/schemas/contracts/config/config.ts` via:

            pnpm run schemas:json:generate

          Use --help with any subcommand for more details.
        HELP
      end
    end
  end
end

Onetime::CLI.register 'config', Onetime::CLI::ConfigGroupCommand
