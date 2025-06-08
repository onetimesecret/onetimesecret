# lib/onetime/cli/validate.rb

module Onetime
  class ValidateCommand < Drydock::Command
    def validate
      # Determine path - from args, OT::Config, or discover first available
      path = argv.first || nil

      if path.nil? || !File.exist?(path)
        path_desc = path.nil? ? "default paths" : path
        OT.le "No configuration file found at #{path_desc}"
        return 1
      end

      # Check for custom schema path from options
      schema_path = option.schema

      OT.li "Validating configuration at #{path}..." if verbose_mode?
      OT.li "Using schema: #{schema_path || 'default'}" if verbose_mode? && schema_path

      begin
        # Load config with optional custom schema
        config_data = OT::Config.load(config_path: path, schema_path: schema_path)
        parsed_template = OT::Config.parsed_template
        schema = OT::Config.schema

        # Show processed content if extra verbose
        if verbose_mode?
          OT.ld "Processed configuration:"
          parsed_template.result.lines.each_with_index do |line, idx|
            OT.ld "  #{idx + 1}: #{line}"
          end
        end

        # Optional: Run additional validation checks beyond schema
        OT::Config.raise_concerns(config_data) if option.full

        # Show parsed config in verbose mode
        if verbose_mode?
          OT.li "\nParsed configuration:"
          puts JSON.pretty_generate(config_data)
        end

        OT.li '' if verbose_mode?
        OT.li "✅ Configuration valid"
        0 # Success exit code

      rescue OT::ConfigValidationError => e
        OT.li '' if verbose_mode?
        OT.le e.message
        OT.le "❌ Configuration validation failed"

        # Show error details based on verbosity level
        if global.verbose && global.verbose > 0
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

        exit 1
      rescue OT::ConfigError => e
        OT.le "❌ Configuration error: #{e.message}"
        exit 2
      rescue StandardError => e
        OT.le "❌ Unexpected error: #{e.message}"
        OT.ld e.backtrace.join("\n") if global.verbose && global.verbose > 0
        exit 3
      ensure
        # Restore original path
        OT::Config.path = original_path if defined?(original_path)
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
