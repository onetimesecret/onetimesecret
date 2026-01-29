# frozen_string_literal: true

require 'json'
require 'fileutils'

module Migration
  module Destinations
    # Collects lookup data from records and writes to JSON file.
    #
    # Extracts key-value pairs from records and writes a lookup file
    # on close. Can also update a registry with collected data.
    #
    # Usage in Kiba job:
    #   destination LookupDestination,
    #     file: 'exports/lookups/email_to_customer_objid.json',
    #     key_field: :email,
    #     value_field: :objid,
    #     registry: registry,
    #     lookup_name: :email_to_customer
    #
    class LookupDestination
      attr_reader :file, :key_field, :value_field, :lookup_name, :registry, :phase, :count

      # @param file [String] Output JSON file path
      # @param key_field [Symbol] Field name for lookup key
      # @param value_field [Symbol] Field name for lookup value
      # @param registry [LookupRegistry, nil] Optional registry to update
      # @param lookup_name [Symbol, nil] Name for registry entry
      # @param phase [Integer] Migration phase number (default: 1)
      #
      def initialize(file:, key_field:, value_field:, registry: nil, lookup_name: nil, phase: 1)
        @file = file
        @key_field = key_field.to_sym
        @value_field = value_field.to_sym
        @registry = registry
        @lookup_name = lookup_name&.to_sym
        @phase = phase
        @data = {}
        @count = 0

        FileUtils.mkdir_p(File.dirname(@file))
      end

      # Collect key-value pair from record.
      #
      # @param record [Hash] Record with key and value fields
      #
      def write(record)
        return if record.nil?

        key = extract_field(record, @key_field)
        value = extract_field(record, @value_field)

        return unless key && value && !key.empty? && !value.empty?

        @data[key.to_s] = value.to_s
        @count += 1
      end

      # Write collected data to file and update registry.
      #
      def close
        return if @data.empty?

        # Write to file
        File.write(@file, JSON.pretty_generate(@data))

        # Update registry if provided
        if @registry && @lookup_name
          @registry.register(@lookup_name, @data, phase: @phase)
        end
      end

      private

      def extract_field(record, field)
        # Check top-level first
        value = record[field]
        return value if value

        # Check nested in v2_fields
        v2_fields = record[:v2_fields]
        return v2_fields[field.to_s] if v2_fields

        # Check nested in fields
        fields = record[:fields]
        fields[field.to_s] if fields
      end
    end
  end
end
