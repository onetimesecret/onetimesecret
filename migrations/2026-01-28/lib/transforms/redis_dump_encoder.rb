# frozen_string_literal: true

module Migration
  module Transforms
    # Encodes hash fields to Redis DUMP format.
    #
    # Takes a record with :v2_fields, creates a Redis hash, dumps it,
    # and stores the base64-encoded dump in :dump.
    #
    # Requires a connected RedisTempKey helper.
    #
    # Usage in Kiba job:
    #   transform RedisDumpEncoder, redis_helper: @redis_helper, fields_key: :v2_fields
    #
    class RedisDumpEncoder < BaseTransform
      attr_reader :redis_helper, :fields_key

      # @param redis_helper [RedisTempKey] Connected Redis helper
      # @param fields_key [Symbol] Key in record containing fields to encode
      # @param kwargs [Hash] Additional options passed to BaseTransform
      #
      def initialize(redis_helper:, fields_key: :v2_fields, **kwargs)
        super(**kwargs)
        @redis_helper = redis_helper
        @fields_key = fields_key
      end

      # Encode fields and replace :dump in record.
      #
      # @param record [Hash] Record with fields to encode
      # @return [Hash] Record with new :dump value
      #
      def process(record)
        fields = record[@fields_key]
        return record unless fields

        begin
          dump_b64 = @redis_helper.create_dump_from_hash(fields)
          record[:dump] = dump_b64
          increment_stat(:encoded)
        rescue StandardError => ex
          record[:encode_error] = ex.message
          increment_stat(:encode_errors)
        end

        record
      end
    end
  end
end
