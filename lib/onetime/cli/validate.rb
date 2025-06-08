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
        config = OT::Config.new(config_path: path, schema_path: schema_path)

        OT.li "Validating configuration at #{config.config_path}..." if verbose_mode?
        OT.li "Using schema: #{config.schema_path}" if verbose_mode?

        # Load and validate - this automatically validates against schema
        config.load!

        # Show processed content if extra verbose
        if verbose_mode? && config.instance_variable_get(:@parsed_template)
          OT.ld "Processed configuration:"
          config.instance_variable_get(:@rendered_yaml).lines.each_with_index do |line, idx|
            OT.ld "  #{idx + 1}: #{line}"
          end
        end

        # Debug: Show what structure we're validating against
        if verbose_mode?
          OT.ld "\nActual config structure being validated:"
          OT.ld "Top-level keys: #{config.unprocessed_config.keys.inspect}"
          OT.ld "Schema expects keys under 'static': #{config.schema.dig('properties', 'static', 'properties')&.keys&.inspect}"
        end

        # Show parsed config in verbose mode
        if verbose_mode?
          OT.li "\nValidated configuration structure:"
          puts JSON.pretty_generate(config.unprocessed_config)
        end

        OT.li '' if verbose_mode?
        OT.li "✅ Configuration valid"
        0 # Success exit code

      rescue OT::ConfigValidationError => e
        OT.le "❌ Configuration validation failed"

        # Show validation errors
        if e.messages.any?
          OT.le "\nValidation errors:"
          e.messages.each_with_index do |msg, idx|
            OT.le "  #{idx + 1}. #{msg}"
          end
        end

        # Show problematic paths in verbose mode
        if verbose_mode? && !e.paths.empty?
          OT.ld "\nProblematic configuration values:"
          display_error_paths(e.paths)
        end

        # Show help message for non-verbose mode
        unless verbose_mode?
          OT.ld "\nUse --verbose to see detailed error information"
        end

        1 # Validation failure exit code

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

    def display_error_paths(paths, prefix = '')
      paths.each do |key, value|
        path = prefix.empty? ? key.to_s : "#{prefix}.#{key}"

        if value.is_a?(Hash)
          display_error_paths(value, path)
        else

          OT.ld "  #{path}: #{value.inspect}"
        end
      end
    end
  end
end
