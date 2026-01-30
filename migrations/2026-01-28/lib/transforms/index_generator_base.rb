# migrations/2026-01-28/lib/transforms/index_generator_base.rb
#
# frozen_string_literal: true

module Migration
  module Transforms
    # Base class for index generators that emit Redis index commands.
    #
    # Index generators are Kiba transforms that yield multiple records:
    # - The original transformed record (passed through)
    # - Zero or more index command records
    #
    # Index command records have the structure:
    #   { command: 'ZADD|HSET|SADD|INCRBY', key: 'index:key', args: [...] }
    #
    # These are routed to a separate indexes JSONL file by RoutingDestination.
    #
    # Usage in Kiba job:
    #   transform Customer::IndexGenerator, stats: stats
    #
    class IndexGeneratorBase < BaseTransform
      # Process a record and yield it along with generated index commands.
      #
      # @param record [Hash] Transformed record with :v2_fields, :objid, etc.
      # @yield [Hash] The original record and index command records
      #
      def process(record)
        # Only generate indexes for :object records that have been transformed
        unless should_generate_indexes?(record)
          yield record
          return nil
        end

        # Pass through the original record
        yield record

        # Generate and yield index commands
        generate_indexes(record).each do |cmd|
          increment_stat(:indexes_generated)
          yield cmd
        end

        nil # Don't return anything (we yielded instead)
      end

      protected

      # Override in subclasses to determine if indexes should be generated.
      #
      # @param record [Hash] The record to check
      # @return [Boolean] True if indexes should be generated
      #
      def should_generate_indexes?(record)
        key = record[:key]
        return false unless key&.end_with?(':object')
        return false unless record[:objid] && !record[:objid].to_s.empty?
        return false unless record[:v2_fields] || record[:dump]

        true
      end

      # Override in subclasses to generate model-specific index commands.
      #
      # @param record [Hash] The transformed record
      # @return [Array<Hash>] Array of index command hashes
      #
      def generate_indexes(record)
        raise NotImplementedError, "#{self.class}#generate_indexes must be implemented"
      end

      # Helper to create a ZADD command.
      #
      # @param key [String] Redis key
      # @param score [Integer, Float] Score for sorted set
      # @param member [String] Member value
      # @return [Hash] ZADD command structure
      #
      def zadd(key, score, member)
        { command: 'ZADD', key: key, args: [score.to_i, member] }
      end

      # Helper to create an HSET command.
      # Values are JSON-encoded for Familia HashKey compatibility.
      #
      # @param key [String] Redis key
      # @param field [String] Hash field
      # @param value [String] Value to store (will be JSON-encoded)
      # @return [Hash] HSET command structure
      #
      def hset(key, field, value)
        { command: 'HSET', key: key, args: [field, value.to_json] }
      end

      # Helper to create a raw HSET command (no JSON encoding).
      #
      # @param key [String] Redis key
      # @param field [String] Hash field
      # @param value [String] Raw value to store
      # @return [Hash] HSET command structure
      #
      def hset_raw(key, field, value)
        { command: 'HSET', key: key, args: [field, value] }
      end

      # Helper to create an SADD command.
      #
      # @param key [String] Redis key
      # @param member [String] Member to add
      # @return [Hash] SADD command structure
      #
      def sadd(key, member)
        { command: 'SADD', key: key, args: [member] }
      end

      # Helper to create an INCRBY command.
      #
      # @param key [String] Redis key
      # @param amount [Integer] Amount to increment
      # @return [Hash] INCRBY command structure
      #
      def incrby(key, amount)
        { command: 'INCRBY', key: key, args: [amount.to_s] }
      end

      # Extract created timestamp from record.
      #
      # @param record [Hash] The record
      # @return [Integer] Unix timestamp
      #
      def extract_created(record)
        created = record[:created] || record.dig(:v2_fields, 'created')
        ts = created.to_i
        ts > 0 ? ts : Time.now.to_i
      end
    end
  end
end
