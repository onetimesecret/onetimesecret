# frozen_string_literal: true

module Migration
  module Transforms
    # Kiba transform for validating records against JSON Schemas.
    #
    # Validates data against a registered schema and either:
    # - Attaches validation errors to the record (default)
    # - Filters out invalid records (strict mode)
    #
    # Usage in Kiba job:
    #   # After decode, validate V1 structure
    #   transform Migration::Transforms::SchemaValidator,
    #             schema: :customer_v1,
    #             field: :fields,
    #             stats: stats
    #
    #   # Before encode, validate V2 structure
    #   transform Migration::Transforms::SchemaValidator,
    #             schema: :customer_v2,
    #             field: :v2_fields,
    #             stats: stats
    #
    class SchemaValidator < BaseTransform
      attr_reader :schema_name, :field, :strict

      # @param schema [Symbol] Name of the registered schema
      # @param field [Symbol] Record field to validate (default: :fields)
      # @param strict [Boolean] Filter out invalid records (default: false)
      # @param kwargs [Hash] Additional options passed to BaseTransform
      #
      def initialize(schema:, field: :fields, strict: false, **kwargs)
        super(**kwargs)
        @schema_name = schema
        @field = field
        @strict = strict

        unless Schemas.registered?(schema)
          raise ArgumentError, "Schema not registered: #{schema}"
        end
      end

      # Validate record data against the schema.
      #
      # @param record [Hash] Input record
      # @return [Hash, nil] Record (with errors attached) or nil if strict
      #
      def process(record)
        data = record[@field]

        # Skip validation if no data to validate
        unless data
          increment_stat(:validation_skipped)
          return record
        end

        errors = Schemas.validate(@schema_name, data)

        if errors.empty?
          increment_stat(:validated)
          record
        else
          handle_validation_errors(record, errors)
        end
      end

      private

      def handle_validation_errors(record, errors)
        increment_stat(:validation_failures)

        # Attach errors to record for inspection
        record[:validation_errors] ||= []
        record[:validation_errors].concat(errors.map { |e| "[#{@schema_name}] #{e}" })

        if @strict
          # Log the key for debugging
          key = record[:key] || 'unknown'
          increment_stat(:filtered_invalid)
          warn "SchemaValidator: Filtered invalid record #{key}: #{errors.first}"
          nil
        else
          record
        end
      end
    end
  end
end
