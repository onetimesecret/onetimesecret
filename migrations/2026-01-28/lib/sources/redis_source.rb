# migrations/2026-01-28/lib/sources/redis_source.rb
#
# frozen_string_literal: true

require 'redis'
require 'base64'

module Migration
  module Sources
    # Kiba source that scans Redis keys and yields records for migration.
    #
    # Scans keys matching a model prefix and yields records containing:
    # - key: Redis key name
    # - type: Redis data type (hash, string, etc.)
    # - ttl_ms: TTL in milliseconds (-1 = no expiry)
    # - db: Source database number
    # - dump: Base64-encoded DUMP data
    # - created: Timestamp from hash objects (for UUIDv7 generation)
    #
    # Usage in Kiba job:
    #   source RedisSource, redis_url: 'redis://localhost:6379', db: 6, model: 'customer'
    #
    class RedisSource
      SCAN_BATCH_SIZE = 1000

      # Models that have a 'created' field in hash objects
      MODELS_WITH_CREATED = %w[customer customdomain metadata secret].freeze

      attr_reader :redis_url, :db, :model, :dry_run

      # @param redis_url [String] Redis connection URL
      # @param db [Integer] Database number to scan
      # @param model [String] Model prefix to filter keys (e.g., 'customer')
      # @param dry_run [Boolean] If true, count keys without dumping
      #
      def initialize(redis_url:, db:, model:, dry_run: false)
        @redis_url = redis_url
        @db = db
        @model = model
        @dry_run = dry_run
        @redis = nil
      end

      # Iterate over all keys matching the model prefix.
      #
      # @yield [Hash] Record with key, type, ttl_ms, db, dump, created
      #
      def each
        connect!

        cursor = '0'
        loop do
          cursor, keys = @redis.scan(cursor, match: "#{@model}:*", count: SCAN_BATCH_SIZE)

          keys.each do |key|
            record = build_record(key)
            yield record if record
          end

          break if cursor == '0'
        end
      ensure
        disconnect!
      end

      private

      def connect!
        @redis = Redis.new(url: "#{@redis_url}/#{@db}")
        @redis.ping # Verify connection
      rescue Redis::CannotConnectError => ex
        raise ArgumentError, "Failed to connect to Redis (DB #{@db}): #{ex.message}"
      end

      def disconnect!
        @redis&.close
        @redis = nil
      end

      def build_record(key)
        key_type = @redis.type(key)

        # Skip if key expired between scan and type check
        return nil if key_type == 'none'

        # Get TTL in milliseconds (-1 = no expiry, -2 = key doesn't exist)
        ttl_ms = @redis.pttl(key)
        return nil if ttl_ms == -2

        # For dry run, return minimal record
        if @dry_run
          return {
            key: key,
            type: key_type,
            ttl_ms: ttl_ms,
            db: @db,
          }
        end

        # Get serialized value
        dump_data = @redis.dump(key)
        return nil if dump_data.nil?

        record = {
          key: key,
          type: key_type,
          ttl_ms: ttl_ms,
          db: @db,
          dump: Base64.strict_encode64(dump_data),
        }

        # Extract 'created' field for hash types that have it (needed for UUIDv7)
        if key_type == 'hash' && key.end_with?(':object')
          if MODELS_WITH_CREATED.include?(@model)
            created = @redis.hget(key, 'created')
            record[:created] = created.to_i if created && !created.empty?
          end
        end

        record
      rescue Redis::CommandError => ex
        warn "Redis error for key #{key}: #{ex.message}"
        nil
      end
    end
  end
end
