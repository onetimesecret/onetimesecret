# migrations/2026-01-28/lib/destinations/redis_destination.rb
#
# frozen_string_literal: true

require 'redis'
require 'base64'

module Migration
  module Destinations
    # Kiba destination that RESTOREs records to Redis/Valkey.
    #
    # Takes records with base64-encoded dump data and restores them
    # to the target Redis instance using the RESTORE command.
    #
    # Expected record format:
    # - key: Redis key name
    # - dump: Base64-encoded DUMP data
    # - ttl_ms: TTL in milliseconds (-1 = no expiry)
    #
    # Usage in Kiba job:
    #   destination RedisDestination,
    #     valkey_url: 'redis://localhost:6379',
    #     db: 6,
    #     dry_run: false
    #
    class RedisDestination
      attr_reader :valkey_url, :db, :dry_run, :stats

      # @param valkey_url [String] Redis/Valkey connection URL
      # @param db [Integer] Target database number
      # @param dry_run [Boolean] If true, count records without restoring
      # @param stats [Hash] Optional stats hash for tracking progress
      #
      def initialize(valkey_url:, db:, dry_run: false, stats: nil)
        @valkey_url = valkey_url
        @db = db
        @dry_run = dry_run
        @stats = stats || { restored: 0, skipped: 0, errors: [] }
        @redis = nil
      end

      # Write (restore) a single record.
      #
      # @param record [Hash] Record with key, dump, ttl_ms
      #
      def write(record)
        return if record.nil?

        key = record[:key]
        dump_b64 = record[:dump]
        ttl_ms = record[:ttl_ms]

        unless key && dump_b64
          @stats[:skipped] += 1
          @stats[:errors] << { key: key, error: 'Missing key or dump data' }
          return
        end

        if @dry_run
          @stats[:restored] += 1
          return
        end

        connect! unless @redis

        # Decode the dump blob
        dump_data = Base64.strict_decode64(dump_b64)

        # Determine TTL for RESTORE command
        # -1 in source means no expiry -> use 0 in RESTORE
        # Otherwise use the ttl_ms value directly
        restore_ttl = ttl_ms == -1 ? 0 : ttl_ms.to_i

        # RESTORE key ttl serialized-value REPLACE
        @redis.restore(key, restore_ttl, dump_data, replace: true)
        @stats[:restored] += 1
      rescue ArgumentError => ex
        @stats[:skipped] += 1
        @stats[:errors] << { key: key, error: "Base64 decode failed: #{ex.message}" }
      rescue Redis::CommandError => ex
        @stats[:skipped] += 1
        @stats[:errors] << { key: key, error: "RESTORE failed: #{ex.message}" }
      end

      # Close the Redis connection.
      #
      def close
        @redis&.close
        @redis = nil
      end

      private

      def connect!
        # Strip any existing database number from the URL before appending the target DB
        base_url = @valkey_url.sub(%r{/\d+$}, '')
        @redis = Redis.new(url: "#{base_url}/#{@db}")
        @redis.ping # Verify connection
      rescue Redis::CannotConnectError => ex
        raise ArgumentError, "Failed to connect to Redis (DB #{@db}): #{ex.message}"
      end
    end
  end
end
