# lib/onetime/configurator/load.rb
#
# frozen_string_literal: true

module Onetime
  class Configurator
    module Load
      extend self

      # Resolve schema path from reference
      # @param schema_ref [String] Schema reference from $schema
      # @param config_path [String] Path to the config file (for relative resolution)
      # @return [String, nil] Resolved schema path or nil if not found
      def resolve_schema_path(schema_ref, config_path)
        return schema_ref if File.exist?(schema_ref)

        # Try relative to config file directory
        config_dir = File.dirname(config_path)
        candidate  = File.join(config_dir, schema_ref)
        return candidate if File.exist?(candidate)

        nil
      end

      def json_load_file(path, *) = json_load(file_read(path), *)
      def yaml_load_file(path) = yaml_load(file_read(path))

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
        raise OT::ConfigError, 'Invalid YAML configuration'
      end

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
