# lib/onetime/cli/validate.rb

module Onetime
  class ValidateCommand < Drydock::Command
    def validate
      # Determine path - from args, OT::Config, or discover first available
      path = argv.first || OT::Config.path

      if path.nil? || !File.exist?(path)
        path_desc = path.nil? ? "default paths" : path
        OT.le "No configuration file found at #{path_desc}"
        return 1
      end

      # Store path for schema loading reference
      OT::Config.path = path

      OT.li "Validating configuration at #{path}..." if verbose_mode?

      begin
        # 1. Apply environment variable normalization
        OT::Config.before_load

        # 2. Load schema file - using exact OT::Config method
        schema = OT::Config.send(:_load_json_schema)

        # 3. Parse configuration file with ERB - using exact OT::Config methods
        parsed_template = OT::Config.send(:_file_read, path)
        config_data = OT::Config.send(:_yaml_load, parsed_template.result)

        # Show processed content if extra verbose
        if verbose_mode?
          OT.li "Processed configuration:"
          parsed_template.result.lines.each_with_index do |line, idx|
            OT.li "  #{idx + 1}: #{line}"
          end
        end

        # 4. Validate configuration against schema - using public OT::Config method
        OT::Config.validate_with_schema(config_data, schema)

        # Optional: Run additional validation checks beyond schema
        if argv.include?('--full-check')
          OT::Config.raise_concerns(config_data)
        end

        OT.li '' if verbose_mode?
        OT.li "✅ Configuration valid"
        return 0
      rescue OT::ConfigValidationError => e
        OT.le ''
        OT.le "❌ Configuration validation failed"

        # Show error details based on verbosity level
        if global.verbose > 0
          OT.ld "\nValidation errors:"
          e.messages.each_with_index do |msg, idx|
            OT.ld "  #{idx + 1}. #{msg}"
          end

          if verbose_mode? && !e.paths.empty?
            OT.ld "\nProblematic paths:"
            display_error_paths(e.paths)
          end
        else
          OT.ld "Use --verbose for error details"
        end

        return 1
      rescue OT::ConfigError => e
        OT.le "❌ Configuration error: #{e.message}"
        return 1
      rescue StandardError => e
        OT.le "❌ Unexpected error: #{e.message}"
        OT.ld e.backtrace.join("\n") if global.verbose > 0
        return 1
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
