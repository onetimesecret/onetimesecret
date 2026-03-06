# lib/onetime/cli/config_command.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    class ConfigCommand < DelayBootCommand
      desc 'Load and display processed configuration'

      argument :path, required: false, desc: 'Path to configuration file'

      option :schema, type: :string, desc: 'Path to JSON schema file'
      option :types, type: :boolean, default: false, desc: 'Show type structure instead of values'
      option :verbose, type: :boolean, default: false, aliases: ['v'], desc: 'Show detailed output'

      def call(path: nil, schema: nil, types: false, verbose: false, **)
        config = OT::Configurator.new(
          config_path: path,
          schema_path: schema,
        )

        puts "Loading #{config.config_path}..." if verbose

        config.load!

        if verbose && config.rendered_template
          puts 'YAML Template:'
          config.rendered_template.split("\n").each_with_index do |line, index|
            puts "Line #{index + 1}: #{line}"
          end
        end

        if types
          puts JSON.pretty_generate(OT::Utils.type_structure(config.configuration))
        else
          puts JSON.pretty_generate(config.configuration)
        end
      rescue OT::ConfigError => ex
        warn "Configuration error: #{ex.message}"
        exit 2
      rescue ArgumentError => ex
        warn ex.message
        exit 3
      rescue StandardError => ex
        warn "Unexpected error: #{ex.message}"
        warn ex.backtrace.join("\n") if verbose
        exit 4
      end
    end

    register 'config', ConfigCommand
    register 'config show', ConfigCommand
  end
end
