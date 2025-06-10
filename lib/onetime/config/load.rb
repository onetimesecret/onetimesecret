# lib/onetime/config/load.rb

module Onetime
  class Config
    module Load
      extend self

      # Convenience methods for loading configuration files
      def json_load_file(path) = json_load(file_read(path))
      def yaml_load_file(path) = yaml_load(file_read(path))

      def json_load(json)
        JSON.parse(json)
      rescue JSON::ParserError => e
        OT.le "Error parsing JSON: #{e.message}"
        raise OT::ConfigError, "Invalid JSON schema: #{e.message}"
      end

      def yaml_load(yaml)
        YAML.safe_load(yaml, permitted_classes: [Symbol])
      rescue Psych::SyntaxError => e
        OT.le "Error parsing YAML: #{e.message}"
        raise OT::ConfigError, "Invalid YAML schema"
      end

      def file_read(path)
        File.read(path.to_s)
      rescue Errno::ENOENT => e
        raise OT::ConfigError, "File not found: #{path || '<nil>'}"
      end
    end
  end
end
