# lib/onetime/configurator/load.rb

module Onetime
  class Configurator
    module Load
      extend self

      # Convenience methods for loading configuration files
      def json_load_file(path) = json_load(file_read(path))
      def yaml_load_file(path) = yaml_load(file_read(path))

      def json_load(json)
        JSON.parse(json)
      rescue JSON::ParserError => ex
        OT.le "Error parsing JSON: #{ex.message}"
        raise OT::ConfigError, "Invalid JSON schema: #{ex.message}"
      end

      def yaml_load(yaml)
        YAML.safe_load(yaml, permitted_classes: [Symbol])
      rescue Psych::SyntaxError => ex
        OT.le "Error parsing YAML: #{ex.message}"
        raise OT::ConfigError, 'Invalid YAML schema'
      end

      def file_read(path)
        File.read(path.to_s)
      rescue Errno::ENOENT
        raise OT::ConfigError, "File not found: #{path || '<nil>'}"
      end
    end
  end
end
