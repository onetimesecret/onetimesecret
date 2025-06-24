# lib/onetime/configurator/load.rb

module Onetime
  class Configurator
    module Load
      extend self

      # @params path [String] Path to file to read
      # @return [Hash] Parsed JSON object (ditto for YAML)
      def json_load_file(path, *) = json_load(file_read(path), *)
      def yaml_load_file(path) = yaml_load(file_read(path))
      def ruby_load_file(path, context = nil) = ruby_load(path, context)

      # @param json [String] JSON string to parse
      # @return [Hash] Parsed JSON object
      def json_load(json, *)
        JSON.parse(json, *)
      rescue JSON::ParserError => ex
        OT.le "Error parsing JSON: #{ex.message}"
        raise OT::ConfigError, 'Invalid JSON schema'
      end

      # @param yaml [String] YAML string to parse
      # @return [Hash] Parsed YAML object
      def yaml_load(yaml)
        YAML.safe_load(yaml, permitted_classes: [Symbol])
      rescue Psych::SyntaxError => ex
        OT.le "Error parsing YAML: #{ex.message}"
        raise OT::ConfigError, 'Invalid YAML schema'
      end

      # @param path [String] Path to Ruby file to load
      # @param context [Object, nil] Optional binding context for evaluation
      # @return [Boolean] True if successful
      def ruby_load(path, context = nil)
        content = file_read(path) # Read file content first
        if context
          context.info_log(path)

          # Execute in the context of the provided object
          context.instance_eval(content, path.to_s)
        else
          # Fallback to global load if no context object is given
          # This branch might be less common for init scripts but kept for flexibility
          Kernel.load(path.to_s)
        end
        true
      rescue LoadError => ex
        OT.le "Error loading Ruby file: #{ex.message}"
        # Preserving original error class for specific LoadError issues if 'load' was used
        # For instance_eval, this is less likely unless script itself has 'load' or 'require'
        raise OT::ConfigError, "Invalid Ruby file (LoadError): #{path} - #{ex.message}"
      rescue SyntaxError => ex
        OT.le "Syntax error in Ruby file: #{ex.message}"
        raise OT::ConfigError, "Ruby syntax error in: #{path}"
      else
        false
      end

      # NOTE: This method loads the entire file into memory at once.
      # For large files (>100MB), consider using streaming approaches or
      # File.foreach for line-by-line processing to avoid memory issues.
      #
      # @param path [String] Path to file to read
      # @return [String] Contents of file
      def file_read(path)
        File.read(path.to_s)
      rescue Errno::ENOENT
        raise OT::ConfigError, "File not found: #{path || '<nil>'}"
      end
    end
  end
end
