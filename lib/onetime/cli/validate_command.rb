# lib/onetime/cli/validate.rb

module Onetime
  class ValidateCommand < Drydock::Command
    def validate
      # Determine path - from args, discovered, or nil for auto-discovery
      path = argv.first

      # Check for custom schema path from options
      schema_path = option.schema

      begin
        # Create config instance with optional paths
        config = OT::Configurator.new(config_path: path, schema_path: schema_path)

        OT.li "Validating #{config.config_path}..."
        OT.li "Schema: #{config.schema_path}"

        # Load and validate - this automatically validates against schema
        config.load!

        # Show processed content if extra verbose
        if option.show && config.parsed_template
          OT.ld 'Template:'
          template_lines = config.parsed_template.result.split("\n")
          template_lines.each_with_index do |line, index|
            OT.ld "Line #{index + 1}: #{line}"
          end

          OT.ld 'Processed configuration:'
          config.rendered_yaml.lines.each_with_index do |line, idx|
            OT.ld "  #{idx + 1}: #{line}"
          end
        end

        # Debug: Show what structure we're validating against
        if verbose_mode?
          OT.ld "\nActual config structure being validated:"
          OT.ld "Top-level keys: #{config.unprocessed_config.keys.inspect}"
          OT.ld "Schema expects keys under 'static': #{config.schema.dig('properties', 'static',
            'properties')&.keys&.inspect}"
        end

        # Show parsed config in verbose mode
        if option.show
          OT.li "\nValidated configuration structure:", JSON.pretty_generate(config.unprocessed_config)
        elsif verbose_mode?
          OT.li "\nValidated configuration structure:", JSON.pretty_generate(OT::Utils.type_structure(config.configuration))
        end

        OT.li '' if verbose_mode?
        OT.li '✅ Configuration valid'
        0 # Success exit code
      rescue OT::ConfigValidationError => ex
        OT.le "❌ #{ex.message}"

        # Show help message for non-verbose mode
        unless verbose_mode?
          OT.ld "\nUse --verbose to see detailed error information"
        end

        1 # Validation failure exit code
      rescue OT::ConfigError => ex
        OT.le "❌ Configuration error: #{ex.message}"
        exit 2 # Config error exit code
      rescue ArgumentError => ex
        # Handle file not found errors
        OT.le "❌ #{ex.message}"
        exit 3 # File not found exit code
      rescue StandardError => ex
        OT.le "❌ Unexpected error: #{ex.message}"
        OT.ld ex.backtrace.join("\n") if verbose_mode?
        exit 4 # Unexpected error exit code
      end
    end

    private

    def verbose_mode?
      global.verbose && global.verbose > 0
    end
  end
end
