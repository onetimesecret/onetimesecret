# frozen_string_literal: true

module Migration
  module Transforms
    # Decodes Redis DUMP data from base64 to hash fields.
    #
    # Takes a JSONL record with :dump field, restores to Redis temp key,
    # reads the hash fields, and adds them to the record as :fields.
    #
    # Requires a connected RedisTempKey helper.
    #
    # Usage in Kiba job:
    #   pre_process { @redis_helper = RedisTempKey.new; @redis_helper.connect! }
    #   transform RedisDumpDecoder, redis_helper: @redis_helper
    #   post_process { @redis_helper.cleanup!; @redis_helper.disconnect! }
    #
    class RedisDumpDecoder < BaseTransform
      attr_reader :redis_helper

      # @param redis_helper [RedisTempKey] Connected Redis helper
      # @param kwargs [Hash] Additional options passed to BaseTransform
      #
      def initialize(redis_helper:, **kwargs)
        super(**kwargs)
        @redis_helper = redis_helper
      end

      # Decode the dump and add :fields to record.
      #
      # @param record [Hash] Record with :dump field
      # @return [Hash] Record with :fields added
      #
      def process(record)
        dump_b64 = record[:dump]
        return record unless dump_b64

        begin
          fields = @redis_helper.restore_and_read_hash(dump_b64, original_key: record[:key])
          record[:fields] = fields
          increment_stat(:decoded)
        rescue Shared::RedisTempKey::RestoreError => ex
          record[:decode_error] = ex.message
          increment_stat(:decode_errors)
        end

        record
      end
    end
  end
end
