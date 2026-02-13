# lib/onetime/cli/validate_command.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    class ValidateCommand < DelayBootCommand
      desc 'Validate configuration against JSON schema'

      argument :path, required: false, desc: 'Path to configuration file'

      option :schema, type: :string, desc: 'Path to JSON schema file'
      option :verbose, type: :boolean, default: false, aliases: ['v'], desc: 'Show detailed output'
      option :show, type: :boolean, default: false, desc: 'Show parsed configuration structure'

      def call(path: nil, schema: nil, verbose: false, show: false, **)
        config = OT::Configurator.new(
          config_path: path,
          schema_path: schema,
        )

        if config.config_path.nil?
          warn 'No configuration file found'
          exit 1
        end

        puts "Validating #{Onetime::Utils.pretty_path(config.config_path)}"
        if config.schema_path && File.exist?(config.schema_path)
          puts "Schema: #{Onetime::Utils.pretty_path(config.schema_path)}"
        end

        config.load!

        if show && config.parsed_yaml
          puts "\nStructure:"
          puts JSON.pretty_generate(config.parsed_yaml)
        elsif verbose
          puts "\nStructure:"
          puts JSON.pretty_generate(OT::Utils.type_structure(config.configuration))
        end

        puts 'Valid'
      rescue OT::ConfigValidationError => ex
        warn "Validation failed: #{ex.message}"
        warn "\nUse --verbose to see detailed error information" unless verbose
        exit 1
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

    register 'config validate', ValidateCommand
  end
end
