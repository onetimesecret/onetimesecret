# migrations/2026-01-28/lib/shared/redis_temp_key.rb
#
# frozen_string_literal: true

require 'redis'
require 'base64'
require 'securerandom'
require 'oj'

module Migration
  module Shared
    # Helper for Redis temporary key operations during migration.
    #
    # Encapsulates the common pattern of restoring Redis DUMP data to a
    # temporary key, reading/writing data, and cleaning up.
    #
    # Usage:
    #   helper = RedisTempKey.new(redis_url: 'redis://localhost:6379', temp_db: 15)
    #   helper.connect!
    #
    #   fields = helper.restore_and_read_hash(dump_b64, original_key: 'customer:foo:object')
    #   dump_b64 = helper.create_dump_from_hash(fields)
    #
    #   helper.cleanup!
    #   helper.disconnect!
    #
    class RedisTempKey
      TEMP_KEY_PREFIX = '_kiba_migrate_tmp_'
      SCAN_COUNT = 100

      attr_reader :redis_url, :temp_db

      def initialize(redis_url: nil, temp_db: nil)
        @redis_url = redis_url || Migration::Config.redis_url
        @temp_db = temp_db || Migration::Config.temp_db
        @redis = nil
        @temp_keys_created = Set.new
      end

      # Connect to Redis.
      #
      # @return [Redis] The Redis client
      #
      def connect!
        @redis = Redis.new(url: "#{@redis_url}/#{@temp_db}")
        @redis.ping
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

      # Restore a DUMP to temporary key, read hash fields, cleanup.
      #
      # @param dump_b64 [String] Base64-encoded Redis DUMP data
      # @param original_key [String] Original key name (for error messages)
      # @return [Hash] Hash fields from the restored key
      # @raise [Base64FormatError] If Base64 encoding is invalid
      # @raise [RestoreError] If Redis restore fails
      #
      def restore_and_read_hash(dump_b64, original_key: 'unknown')
        ensure_connected!
        validate_base64!(dump_b64, original_key)
        temp_key = generate_temp_key

        dump_data = Base64.strict_decode64(dump_b64)

        begin
          @redis.restore(temp_key, 0, dump_data, replace: true)
          @temp_keys_created << temp_key
          @redis.hgetall(temp_key)
        rescue Redis::CommandError => ex
          raise RestoreError.new(original_key, ex.message)
        ensure
          safe_delete(temp_key)
        end
      end

      # Create a hash in Redis, dump it, return base64.
      #
      # Field values are JSON-serialized for Familia v2 compatibility.
      # This ensures strings like "email@example.com" are stored as
      # "\"email@example.com\"" which Familia v2 can properly deserialize.
      #
      # @param fields [Hash] Hash fields to store
      # @param serialize_values [Boolean] JSON-serialize values for Familia v2 (default: true)
      # @return [String] Base64-encoded DUMP data
      #
      def create_dump_from_hash(fields, serialize_values: true)
        ensure_connected!

        # Filter out nil values
        clean_fields = fields.compact

        if clean_fields.empty?
          raise ArgumentError, 'Cannot create dump from empty hash'
        end

        # JSON-serialize each field value for Familia v2 compatibility
        stored_fields = if serialize_values
                          serialize_field_values(clean_fields)
                        else
                          clean_fields
                        end

        temp_key = generate_temp_key

        begin
          @redis.hset(temp_key, stored_fields)
          @temp_keys_created << temp_key
          dump_data = @redis.dump(temp_key)
          Base64.strict_encode64(dump_data)
        ensure
          safe_delete(temp_key)
        end
      end

      # Clean up all temporary keys.
      #
      # @return [Integer] Number of keys deleted
      #
      def cleanup!
        return 0 unless @redis

        deleted = 0
        cursor = '0'

        loop do
          cursor, keys = @redis.scan(cursor, match: "#{TEMP_KEY_PREFIX}*", count: SCAN_COUNT)
          unless keys.empty?
            @redis.del(*keys)
            deleted += keys.size
          end
          break if cursor == '0'
        end

        @temp_keys_created.clear
        deleted
      end

      # Execute block with automatic cleanup.
      #
      # @yield Block to execute
      # @return Result of the block
      #
      def with_cleanup
        yield
      ensure
        cleanup!
      end

      private

      # Validate Base64 encoding format before decoding.
      #
      # @param data [String] Base64-encoded data
      # @param key [String] Original key name (for error messages)
      # @raise [Base64FormatError] If encoding is invalid
      #
      def validate_base64!(data, key)
        return if data.nil? || data.empty?

        # Check for valid Base64 characters and padding
        unless data.match?(/\A[A-Za-z0-9+\/]*={0,2}\z/)
          raise Base64FormatError.new(key, 'Invalid Base64 characters or padding')
        end

        # Check length is valid (Base64 length must be multiple of 4)
        unless (data.length % 4).zero?
          raise Base64FormatError.new(key, "Invalid Base64 length: #{data.length}")
        end
      end

      def ensure_connected!
        raise NotConnectedError unless @redis
      end

      def generate_temp_key
        "#{TEMP_KEY_PREFIX}#{SecureRandom.hex(8)}"
      end

      def safe_delete(key)
        @redis&.del(key)
        @temp_keys_created.delete(key)
      rescue StandardError
        # Ignore cleanup errors
      end

      # JSON-serialize field values for Familia v2 compatibility.
      #
      # Familia v2 expects all hash field values to be JSON strings:
      #   - "email@example.com" -> "\"email@example.com\""
      #   - 123 -> "123"
      #   - true -> "true"
      #   - nil -> "null" (but nils are filtered before this)
      #
      # @param fields [Hash] Hash with field values
      # @return [Hash] Hash with JSON-serialized values
      #
      def serialize_field_values(fields)
        fields.transform_values do |value|
          Oj.dump(value, mode: :strict)
        end
      end

      # Error classes
      class RedisTempKeyError < StandardError; end

      class NotConnectedError < RedisTempKeyError
        def initialize
          super('Redis not connected. Call connect! first.')
        end
      end

      class RestoreError < RedisTempKeyError
        attr_reader :key, :redis_message

        def initialize(key, redis_message)
          @key = key
          @redis_message = redis_message
          super("Restore failed for key '#{key}': #{redis_message}")
        end
      end

      class Base64FormatError < RedisTempKeyError
        attr_reader :key, :reason

        def initialize(key, reason)
          @key = key
          @reason = reason
          super("Invalid Base64 for key '#{key}': #{reason}")
        end
      end
    end
  end
end
