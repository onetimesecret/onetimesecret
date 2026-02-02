# migrations/2026-01-28/lib/transforms/schema_validator.rb
#
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

      # Maximum number of sample errors to collect for reporting
      MAX_ERROR_SAMPLES = 5

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

        # Store error tracking in stats hash for access after job completes
        stats_key = :"#{schema_name}_errors"
        @stats[stats_key] ||= { samples: [], counts: Hash.new(0) }
        @error_data = @stats[stats_key]

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

        # Track error frequency by type
        errors.each do |err|
          # Extract field path from error (e.g., "/burned:" -> "burned")
          field_path = err[%r{^/(\w+):}, 1] || 'unknown'
          @error_data[:counts][field_path] += 1
        end

        # Collect sample errors for reporting
        if @error_data[:samples].size < MAX_ERROR_SAMPLES
          key = record[:key] || 'unknown'
          @error_data[:samples] << { key: key, errors: errors }
        end

        # Attach errors to record for inspection
        record[:validation_errors] ||= []
        record[:validation_errors].concat(errors.map { |e| "[#{@schema_name}] #{e}" })

        if @strict
          key = record[:key] || 'unknown'
          increment_stat(:filtered_invalid)
          warn "SchemaValidator: Filtered invalid record #{key}: #{errors.first}"
          nil
        else
          record
        end
      end

      # Print validation summary from stats hash.
      # Call from job's print_summary method.
      #
      # @param stats [Hash] Stats hash containing error data
      # @param schema_name [Symbol] Schema name to report on
      #
      def self.print_summary(stats, schema_name)
        stats_key = :"#{schema_name}_errors"
        error_data = stats[stats_key]
        return unless error_data && !error_data[:counts].empty?

        puts "\n  [#{schema_name}] Validation Issues:"
        puts "    Fields with errors (by frequency):"
        error_data[:counts].sort_by { |_, count| -count }.first(10).each do |field, count|
          puts "      #{field}: #{count}"
        end

        return if error_data[:samples].empty?

        puts "    Sample errors (first #{error_data[:samples].size}):"
        error_data[:samples].each do |sample|
          puts "      #{sample[:key]}:"
          sample[:errors].first(3).each { |e| puts "        - #{e}" }
        end
      end
    end
  end
end
