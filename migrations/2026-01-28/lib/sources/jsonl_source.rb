# frozen_string_literal: true

require 'json'

module Migration
  module Sources
    # Generic JSONL file source for Kiba pipelines.
    #
    # Reads a JSONL file line by line, yielding parsed JSON objects.
    # Supports optional filtering by key pattern.
    #
    # Usage in Kiba job:
    #   source JsonlSource, file: 'exports/customer/customer_dump.jsonl'
    #   source JsonlSource, file: 'dump.jsonl', key_pattern: /^customer:/
    #
    class JsonlSource
      attr_reader :file, :key_pattern

      # @param file [String] Path to JSONL file
      # @param key_pattern [Regexp, nil] Optional pattern to filter records by key
      #
      def initialize(file:, key_pattern: nil)
        @file = file
        @key_pattern = key_pattern

        unless File.exist?(@file)
          raise ArgumentError, "Input file not found: #{@file}"
        end
      end

      # Iterate over records in the file.
      #
      # @yield [Hash] Each parsed record (symbolized keys)
      #
      def each
        File.foreach(@file) do |line|
          # Scrub invalid UTF-8 sequences to prevent encoding errors
          line = line.scrub('?')
          next if line.strip.empty?

          record = JSON.parse(line.chomp, symbolize_names: true)

          # Apply key pattern filter if specified
          if @key_pattern
            key = record[:key]
            next unless key && key.match?(@key_pattern)
          end

          yield record
        rescue JSON::ParserError => ex
          # Log but don't halt - let downstream handle errors
          warn "JSON parse error in #{@file}: #{ex.message}"
        end
      end
    end
  end
end
