# frozen_string_literal: true

require 'json_schemer'

module Migration
  module Schemas
    # Schema validation infrastructure for the migration pipeline.
    #
    # Provides a centralized registry and validation API for JSON Schemas.
    # Uses json_schemer gem for JSON Schema Draft 7 validation.
    #
    # Usage:
    #   errors = Migration::Schemas.validate(:customer_v1, fields_hash)
    #   if errors.empty?
    #     # Data is valid
    #   else
    #     errors.each { |e| puts e }
    #   end
    #
    class << self
      # Register a schema with a given name.
      #
      # @param name [Symbol] Schema name (e.g., :customer_v1)
      # @param schema [Hash] JSON Schema definition
      #
      def register(name, schema)
        schemas[name] = JSONSchemer.schema(schema)
      end

      # Validate data against a named schema.
      #
      # @param name [Symbol] Schema name
      # @param data [Hash] Data to validate
      # @return [Array<String>] Array of error messages (empty if valid)
      #
      def validate(name, data)
        schemer = schemas[name]
        raise SchemaNotFoundError, "Schema not found: #{name}" unless schemer

        schemer.validate(data).map do |error|
          format_error(error)
        end
      end

      # Check if data is valid against a named schema.
      #
      # @param name [Symbol] Schema name
      # @param data [Hash] Data to validate
      # @return [Boolean]
      #
      def valid?(name, data)
        schemer = schemas[name]
        raise SchemaNotFoundError, "Schema not found: #{name}" unless schemer

        schemer.valid?(data)
      end

      # List all registered schema names.
      #
      # @return [Array<Symbol>]
      #
      def registered
        schemas.keys
      end

      # Check if a schema is registered.
      #
      # @param name [Symbol] Schema name
      # @return [Boolean]
      #
      def registered?(name)
        schemas.key?(name)
      end

      # Clear all registered schemas (useful for testing).
      #
      def reset!
        @schemas = {}
      end

      private

      def schemas
        @schemas ||= {}
      end

      def format_error(error)
        location = error['data_pointer']
        location = 'root' if location.nil? || location.empty?

        message = error['error'] || error['type'] || 'validation failed'

        "#{location}: #{message}"
      end
    end

    class SchemaNotFoundError < StandardError; end
  end
end
