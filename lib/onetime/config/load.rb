# lib/onetime/config/load.rb

module Onetime
  class Config
    module Load
      extend self
      def load_custom_schema(schema_path)
      rescue JSON::ParserError => e
        raise OT::ConfigError, "Invalid JSON schema: #{e.message}"
      end

      def load_static_configuration(path=nil)
      rescue OT::ConfigError => e
        if OT.debug? && @parsed_template
          template_lines = @parsed_template.result.split("\n")
          template_lines.each_with_index do |line, index|
            OT.ld "Line #{index + 1}: #{line}"
          end
        end

        OT.le e.message
        OT.ld e.backtrace.join("\n")
        raise e
      end

      def json_load_file(path)
        json = File.read(path)
        json_load(json)
      end

      def json_load(json)
        JSON.parse(json)
      rescue JSON::ParserError => e
        OT.le "Error parsing JSON: #{e.message}"
        raise OT::ConfigError, "Invalid JSON schema: #{e.message}"
      end

      def yaml_load_file(path)
        yaml = File.read(path)
        yaml_load(yaml)
      end

      def yaml_load(yaml)
        YAML.safe_load(yaml)
      rescue Psych::SyntaxError => e
        OT.le "Error parsing YAML: #{e.message}"
        raise OT::ConfigError, "Invalid YAML schema: #{e.message}"
      end

      def file_read(path)
        File.read(path)
      rescue Errno::ENOENT => e
        OT.le "Config file not found: #{path}"
        raise ArgumentError, "Configuration file not found: #{path}"
      end
    end
  end
end
