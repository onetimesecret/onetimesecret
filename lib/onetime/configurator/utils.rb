# lib/onetime/configurator/utils.rb
#
# frozen_string_literal: true

require 'json_schemer'

module Onetime
  class Configurator
    module Utils
      extend self

      # Validates a configuration against a JSON schema with optional default value insertion
      #
      # @param conf [Hash] The configuration hash to validate
      # @param schema [Hash] The JSON schema to validate against
      # @param apply_defaults [Boolean] Whether to insert default values from the schema
      # @return [Hash] The validated configuration (potentially modified with defaults)
      # @raise [OT::ConfigError] If the schema is nil
      # @raise [OT::ConfigValidationError] If the configuration fails schema validation
      def validate_against_schema(conf, schema, apply_defaults: false)
        raise OT::ConfigError, 'Configuration is nil' if conf.nil?
        raise OT::ConfigError, 'Schema is nil' if schema.nil?

        schemer = JSONSchemer.schema(
          schema,
          meta_schema: 'https://json-schema.org/draft/2020-12/schema',
          insert_property_defaults: apply_defaults,
          format: true,
          # Convert symbols to strings for string-typed fields (backwards compat
          # for YAML configs that historically used symbol values).
          before_property_validation: proc do |data, property, property_schema, _parent|
            val = data[property]
            case property_schema['type']
            when 'string'
              data[property] = val.to_s if val.is_a?(Symbol)
            end
          end,
        )

        errors = schemer.validate(conf).to_a
        return conf if errors.empty?

        error_messages = format_validation_errors(errors)
        error_paths    = extract_error_paths(errors)

        raise OT::ConfigValidationError.new(
          messages: error_messages,
          paths: error_paths,
        )
      end

      def format_validation_errors(errors)
        errors.map { |err| err['error'] }
      end

      def extract_error_paths(errors)
        error_paths = {}
        errors.each do |err|
          path_segments = err['data_pointer'].split('/').reject(&:empty?)
          next if path_segments.empty?

          current         = error_paths
          parent_segments = path_segments[0..-2]
          parent_segments.each do |segment|
            current[segment] ||= {}
            current            = current[segment]
          end

          current[path_segments.last] = err['data']
        end
        error_paths
      end
    end
  end
end
