# frozen_string_literal: true

require 'json'
require 'fileutils'

module Migration
  module Destinations
    # Writes records to a JSONL file.
    #
    # Supports field filtering to exclude internal fields from output.
    #
    # Usage in Kiba job:
    #   destination JsonlDestination,
    #     file: 'exports/customer/customer_transformed.jsonl',
    #     exclude_fields: [:fields, :v2_fields]
    #
    class JsonlDestination
      attr_reader :file, :exclude_fields, :count

      # @param file [String] Output file path
      # @param exclude_fields [Array<Symbol>] Fields to exclude from output
      #
      def initialize(file:, exclude_fields: [])
        @file = file
        @exclude_fields = exclude_fields.map(&:to_sym)
        @count = 0
        @io = nil

        FileUtils.mkdir_p(File.dirname(@file))
      end

      # Write a single record.
      #
      # @param record [Hash] Record to write
      #
      def write(record)
        return if record.nil?

        @io ||= File.open(@file, 'w')

        output = filter_fields(record)
        @io.puts(JSON.generate(output))
        @count += 1
      end

      # Close the output file.
      #
      def close
        @io&.close
        @io = nil
      end

      private

      def filter_fields(record)
        return record if @exclude_fields.empty?

        record.reject { |k, _| @exclude_fields.include?(k.to_sym) }
      end
    end
  end
end
