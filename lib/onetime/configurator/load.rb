# lib/onetime/configurator/load.rb

module Onetime
  class Configurator
    module Load
      extend self

      # @params path [String] Path to file to read
      # @return [Hash] Parsed JSON object (ditto for YAML)
      def json_load_file(path) = json_load(file_read(path))
      def yaml_load_file(path) = yaml_load(file_read(path))

      # @param json [String] JSON string to parse
      # @return [Hash] Parsed JSON object
      def json_load(json)
        JSON.parse(json)
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
