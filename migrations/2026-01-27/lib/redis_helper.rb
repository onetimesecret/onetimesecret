# migrations/2026-01-27/lib/redis_helper.rb
#
# frozen_string_literal: true

require 'redis'
require 'base64'
require 'securerandom'

module Migration
  # Shared Redis operations for migration scripts.
  #
  # Encapsulates the common pattern of restoring Redis DUMP data to a
  # temporary key, reading the data, and cleaning up. Also provides
  # the reverse: creating a hash, dumping it, and returning base64.
  #
  # All operations use a configurable temp key prefix and ensure cleanup
  # even on errors. The temp database is isolated from production data.
  #
  # Usage:
  #   helper = Migration::RedisHelper.new(redis_url: 'redis://localhost:6379', temp_db: 15)
  #   helper.connect!
  #
  #   # Read a hash from DUMP data
  #   fields = helper.restore_and_read_hash(record)
  #
  #   # Create DUMP from transformed fields
  #   dump_b64 = helper.create_dump_from_hash(v2_fields)
  #
  #   helper.cleanup_temp_keys!
  #   helper.disconnect!
  #
  class RedisHelper
    DEFAULT_TEMP_KEY_PREFIX = '_migrate_tmp_'
    DEFAULT_SCAN_COUNT = 100

    attr_reader :redis_url, :temp_db, :temp_key_prefix

    def initialize(redis_url: 'redis://127.0.0.1:6379', temp_db: 15, temp_key_prefix: nil)
      @redis_url = redis_url
      @temp_db = temp_db
      @temp_key_prefix = temp_key_prefix || DEFAULT_TEMP_KEY_PREFIX
      @redis = nil
      @temp_keys_created = Set.new
    end

    # Connect to Redis.
    #
    # @return [Redis] The Redis client
    # @raise [Redis::CannotConnectError] If connection fails
    #
    def connect!
      @redis = Redis.new(url: "#{@redis_url}/#{@temp_db}")
      @redis.ping # Verify connection
      @redis
    end

    # Disconnect from Redis.
    #
    def disconnect!
      return unless @redis
      @redis.close
      @redis = nil
    end

    # Check if connected.
    #
    # @return [Boolean]
    #
    def connected?
      @redis&.connected?
    end

    # Restore a DUMP to a temporary key, read hash fields, cleanup.
    #
    # This is the core pattern used across all transform scripts to
    # decode Redis serialized hash data from JSONL export files.
    #
    # @param record [Hash] JSONL record with :dump (base64) and :key fields
    # @return [Hash] Hash fields from the restored key
    # @raise [RedisRestoreError] If restore fails
    # @raise [NotConnectedError] If not connected
    #
    def restore_and_read_hash(record)
      ensure_connected!
      temp_key = generate_temp_key

      dump_data = decode_dump(record)

      begin
        @redis.restore(temp_key, 0, dump_data, replace: true)
        @temp_keys_created << temp_key
        @redis.hgetall(temp_key)
      rescue Redis::CommandError => ex
        raise RedisRestoreError.new(record[:key], ex.message)
      ensure
        safe_delete(temp_key)
      end
    end

    # Create a hash in Redis, dump it, return base64.
    #
    # This is the reverse operation - takes transformed fields and
    # creates a Redis DUMP that can be used with RESTORE during load.
    #
    # @param fields [Hash] Hash fields to store
    # @return [String] Base64-encoded DUMP data
    # @raise [NotConnectedError] If not connected
    #
    def create_dump_from_hash(fields)
      ensure_connected!
      temp_key = generate_temp_key

      # Filter out nil values - Redis doesn't accept them
      clean_fields = fields.compact

      begin
        # Use hmset for compatibility (maps to HSET in modern Redis)
        @redis.hmset(temp_key, clean_fields.to_a.flatten)
        @temp_keys_created << temp_key
        dump_data = @redis.dump(temp_key)
        Base64.strict_encode64(dump_data)
      ensure
        safe_delete(temp_key)
      end
    end

    # Restore a sorted set from DUMP, read members with scores, cleanup.
    #
    # @param record [Hash] JSONL record with :dump (base64) and :key fields
    # @return [Array<[member, score]>] Array of [member, score] pairs
    # @raise [RedisRestoreError] If restore fails
    #
    def restore_and_read_zset(record)
      ensure_connected!
      temp_key = generate_temp_key

      dump_data = decode_dump(record)

      begin
        @redis.restore(temp_key, 0, dump_data, replace: true)
        @temp_keys_created << temp_key
        @redis.zrange(temp_key, 0, -1, with_scores: true)
      rescue Redis::CommandError => ex
        raise RedisRestoreError.new(record[:key], ex.message)
      ensure
        safe_delete(temp_key)
      end
    end

    # Restore a set from DUMP, read members, cleanup.
    #
    # @param record [Hash] JSONL record with :dump (base64) and :key fields
    # @return [Set] Set members
    # @raise [RedisRestoreError] If restore fails
    #
    def restore_and_read_set(record)
      ensure_connected!
      temp_key = generate_temp_key

      dump_data = decode_dump(record)

      begin
        @redis.restore(temp_key, 0, dump_data, replace: true)
        @temp_keys_created << temp_key
        @redis.smembers(temp_key).to_set
      rescue Redis::CommandError => ex
        raise RedisRestoreError.new(record[:key], ex.message)
      ensure
        safe_delete(temp_key)
      end
    end

    # Pipeline multiple hash reads for efficiency.
    #
    # @param records [Array<Hash>] Array of JSONL records
    # @yield [record, fields] Block called for each record with its fields
    # @return [Array<Hash>] Array of field hashes
    #
    def batch_restore_hashes(records, &block)
      ensure_connected!

      records.map do |record|
        fields = restore_and_read_hash(record)
        block&.call(record, fields)
        fields
      end
    end

    # Clean up all temporary keys created by this helper.
    #
    # @return [Integer] Number of keys deleted
    #
    def cleanup_temp_keys!
      return 0 unless @redis

      deleted = 0
      cursor = '0'

      loop do
        cursor, keys = @redis.scan(cursor, match: "#{@temp_key_prefix}*", count: DEFAULT_SCAN_COUNT)
        unless keys.empty?
          @redis.del(*keys)
          deleted += keys.size
        end
        break if cursor == '0'
      end

      @temp_keys_created.clear
      deleted
    end

    # Execute a block with automatic cleanup on error.
    #
    # @yield Block to execute
    # @return Result of the block
    #
    def with_cleanup
      yield
    ensure
      cleanup_temp_keys!
    end

    # Get the underlying Redis client (for advanced operations).
    #
    # @return [Redis, nil]
    #
    def redis
      @redis
    end

    private

    def ensure_connected!
      raise NotConnectedError unless @redis
    end

    def generate_temp_key
      "#{@temp_key_prefix}#{SecureRandom.hex(8)}"
    end

    def decode_dump(record)
      dump_b64 = record[:dump] || record['dump']
      raise ArgumentError, "Record missing :dump field" unless dump_b64
      Base64.strict_decode64(dump_b64)
    end

    def safe_delete(key)
      @redis&.del(key)
      @temp_keys_created.delete(key)
    rescue StandardError
      # Ignore cleanup errors
    end

    # Custom error classes
    class RedisError < StandardError; end

    class NotConnectedError < RedisError
      def initialize
        super("Redis not connected. Call connect! first.")
      end
    end

    class RedisRestoreError < RedisError
      attr_reader :key, :redis_message

      def initialize(key, redis_message)
        @key = key
        @redis_message = redis_message
        super("Restore failed for key '#{key}': #{redis_message}")
      end
    end
  end
end
