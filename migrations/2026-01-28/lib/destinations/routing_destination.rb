# migrations/2026-01-28/lib/destinations/routing_destination.rb
#
# frozen_string_literal: true

require 'json'
require 'fileutils'

module Migration
  module Destinations
    # Routes records to different destinations based on record type.
    #
    # Index generators yield two types of records:
    # - Data records: have :dump field (transformed model data)
    # - Index commands: have :command field (ZADD, HSET, SADD, INCRBY)
    #
    # This destination routes each type to its appropriate JSONL file.
    #
    # Usage in Kiba job:
    #   destination RoutingDestination, routes: {
    #     data: [JsonlDestination, { file: 'customer_transformed.jsonl', ... }],
    #     indexes: [JsonlDestination, { file: 'customer_indexes.jsonl' }],
    #   }
    #
    class RoutingDestination
      attr_reader :destinations, :stats

      # @param routes [Hash] Map of route names to [DestinationClass, options] pairs
      # @param stats [Hash] Optional stats hash for tracking
      #
      def initialize(routes:, stats: nil)
        @stats = stats || {}
        @destinations = {}

        routes.each do |route_name, (klass, options)|
          @destinations[route_name] = klass.new(**(options || {}))
        end
      end

      # Write a record to the appropriate destination based on its type.
      #
      # @param record [Hash] Record to route
      #
      def write(record)
        return if record.nil?

        route = determine_route(record)
        destination = @destinations[route]

        if destination
          destination.write(record)
          increment_stat(:"#{route}_written")
        else
          increment_stat(:unrouted_records)
        end
      end

      # Close all destinations.
      #
      def close
        @destinations.each_value(&:close)
      end

      private

      # Determine which route a record should go to.
      #
      # @param record [Hash] The record to route
      # @return [Symbol] Route name (:data, :indexes, or :unknown)
      #
      def determine_route(record)
        if record[:command]
          # Index command record (ZADD, HSET, SADD, INCRBY)
          :indexes
        elsif record[:dump] || record[:key]
          # Data record (has Redis DUMP or key)
          :data
        else
          :unknown
        end
      end

      def increment_stat(key)
        @stats[key] = (@stats[key] || 0) + 1
      end
    end
  end
end
