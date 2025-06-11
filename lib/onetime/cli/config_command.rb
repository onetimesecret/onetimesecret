# lib/onetime/cli/validate.rb

module Onetime
  class ConfigCommand < Drydock::Command
    def config
      # Determine path - from args, discovered, or nil for auto-discovery
      path = argv.first

      # Check for custom schema path from options
      schema_path = option.schema

      begin
        # Create config instance with optional paths
        config = OT::Configurator.new(config_path: path, schema_path: schema_path)

        OT.li "#{config.config_path}..." if verbose_mode?
        OT.ld "Schema: #{config.schema_path}"

        # Load and validate - this automatically validates against schema
        config.load!

        # Show processed content if extra verbose
        if verbose_mode?
          OT.li 'YAML Template:'
          template_lines = config.rendered_yaml.split("\n")
          template_lines.each_with_index do |line, index|
            OT.li "Line #{index + 1}: #{line}"
          end
        end

        if option.types
          puts JSON.pretty_generate(OT::Utils.type_structure(config.config))
        else
          puts JSON.pretty_generate(config.config)
        end

      rescue OT::ConfigError => e
        OT.le "❌ Configuration error: #{e.message}"
        exit 2 # Config error exit code

      rescue ArgumentError => e
        # Handle file not found errors
        OT.le "❌ #{e.message}"
        exit 3 # File not found exit code

      rescue StandardError => e
        OT.le "❌ Unexpected error: #{e.message}"
        OT.ld e.backtrace.join("\n") if verbose_mode?
        exit 4 # Unexpected error exit code
      end
    end

    private

    def verbose_mode?
      global.verbose && global.verbose > 0
    end


  end
end
