# frozen_string_literal: true

module Migration
  module Destinations
    # Wraps multiple destinations to write records to all of them.
    #
    # Kiba pipelines typically have a single destination, but migration
    # jobs often need to write both transformed data and lookup files.
    # This composite pattern enables fan-out to multiple destinations.
    #
    # Usage in Kiba job:
    #   destination CompositeDestination,
    #     destinations: [
    #       [JsonlDestination, { file: 'output.jsonl' }],
    #       [LookupDestination, { file: 'lookup.json', key_field: :email, value_field: :objid }]
    #     ]
    #
    class CompositeDestination
      attr_reader :destinations

      # @param destinations [Array<Array>] Array of [DestinationClass, options] pairs
      #
      def initialize(destinations:)
        @destinations = destinations.map do |klass, options|
          klass.new(**options)
        end
      end

      # Write record to all destinations.
      #
      # @param record [Hash] Record to write
      #
      def write(record)
        @destinations.each { |dest| dest.write(record) }
      end

      # Close all destinations.
      #
      def close
        @destinations.each(&:close)
      end

      # Get a destination by class.
      #
      # @param klass [Class] Destination class to find
      # @return [Object, nil] The destination instance or nil
      #
      def find_destination(klass)
        @destinations.find { |dest| dest.is_a?(klass) }
      end
    end
  end
end
