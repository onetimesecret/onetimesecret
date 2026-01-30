# migrations/2026-01-28/spec/transforms/redis_dump_encoder_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Migration::Transforms::RedisDumpEncoder do
  let(:stats) { {} }
  let(:redis_helper) { Migration::Shared::RedisTempKey.new(redis_url: 'redis://127.0.0.1:6379', temp_db: 15) }

  before(:each) do
    skip 'Redis not available' unless RedisTestHelper.redis_available?
    redis_helper.connect!
  end

  after(:each) do
    redis_helper.cleanup! if redis_helper.connected?
    redis_helper.disconnect! if redis_helper.connected?
  end

  describe '#initialize' do
    it 'accepts redis_helper parameter' do
      encoder = described_class.new(redis_helper: redis_helper, stats: stats)

      expect(encoder.redis_helper).to be(redis_helper)
    end

    it 'defaults fields_key to :v2_fields' do
      encoder = described_class.new(redis_helper: redis_helper, stats: stats)

      expect(encoder.fields_key).to eq(:v2_fields)
    end

    it 'accepts custom fields_key parameter' do
      encoder = described_class.new(redis_helper: redis_helper, fields_key: :custom_fields, stats: stats)

      expect(encoder.fields_key).to eq(:custom_fields)
    end
  end

  describe '#process' do
    context 'with valid fields' do
      it 'encodes :v2_fields to base64 DUMP and replaces :dump field' do
        encoder = described_class.new(redis_helper: redis_helper, stats: stats)
        record = {
          key: 'customer:objid123:object',
          dump: 'old-dump-data',
          v2_fields: { 'name' => 'Alice', 'email' => 'alice@example.com' }
        }

        result = encoder.process(record)

        expect(result[:dump]).to be_a(String)
        expect(result[:dump]).not_to eq('old-dump-data')
        # Verify it's valid base64
        expect { Base64.strict_decode64(result[:dump]) }.not_to raise_error
      end

      it 'produces dump with JSON-encoded field values for Familia v2' do
        encoder = described_class.new(redis_helper: redis_helper, stats: stats)
        fields = { 'name' => 'Bob', 'count' => '42' }
        record = { key: 'test:1', v2_fields: fields }

        result = encoder.process(record)

        # Decode and verify - values are JSON-encoded for Familia v2 compatibility
        decoded_fields = redis_helper.restore_and_read_hash(result[:dump], original_key: 'test')
        expect(decoded_fields['name']).to eq('"Bob"')
        expect(decoded_fields['count']).to eq('"42"')
      end

      it 'increments :encoded stat on success' do
        encoder = described_class.new(redis_helper: redis_helper, stats: stats)
        record = { key: 'test:1', v2_fields: { 'id' => '1' } }

        encoder.process(record)

        expect(stats[:encoded]).to eq(1)
      end
    end

    context 'with custom fields_key' do
      it 'encodes from the specified field key' do
        encoder = described_class.new(redis_helper: redis_helper, fields_key: :custom_fields, stats: stats)
        record = {
          key: 'test:1',
          v2_fields: { 'wrong' => 'data' },
          custom_fields: { 'correct' => 'data' }
        }

        result = encoder.process(record)

        decoded = redis_helper.restore_and_read_hash(result[:dump], original_key: 'test')
        # Value is JSON-encoded for Familia v2
        expect(decoded['correct']).to eq('"data"')
        expect(decoded).not_to have_key('wrong')
      end
    end

    context 'with missing fields_key' do
      it 'passes record through unchanged when :v2_fields is missing' do
        encoder = described_class.new(redis_helper: redis_helper, stats: stats)
        original_dump = 'original-dump-value'
        record = { key: 'test:1', dump: original_dump }

        result = encoder.process(record)

        expect(result[:dump]).to eq(original_dump)
      end

      it 'passes record through unchanged when :v2_fields is nil' do
        encoder = described_class.new(redis_helper: redis_helper, stats: stats)
        record = { key: 'test:1', v2_fields: nil }

        result = encoder.process(record)

        expect(result).to eq(record)
      end

      it 'does not modify stats when skipping' do
        encoder = described_class.new(redis_helper: redis_helper, stats: stats)
        record = { key: 'test:1' }

        encoder.process(record)

        expect(stats).to be_empty
      end
    end

    context 'with encode error' do
      it 'attaches :encode_error to record' do
        # Create a mock redis_helper that raises an error
        failing_helper = instance_double(Migration::Shared::RedisTempKey)
        allow(failing_helper).to receive(:create_dump_from_hash)
          .and_raise(StandardError.new('Redis encoding failed'))

        encoder = described_class.new(redis_helper: failing_helper, stats: stats)
        record = { key: 'test:1', v2_fields: { 'id' => '1' } }

        result = encoder.process(record)

        expect(result[:encode_error]).to eq('Redis encoding failed')
      end

      it 'increments :encode_errors stat on failure' do
        failing_helper = instance_double(Migration::Shared::RedisTempKey)
        allow(failing_helper).to receive(:create_dump_from_hash)
          .and_raise(StandardError.new('Connection lost'))

        encoder = described_class.new(redis_helper: failing_helper, stats: stats)
        record = { key: 'test:1', v2_fields: { 'id' => '1' } }

        encoder.process(record)

        expect(stats[:encode_errors]).to eq(1)
      end

      it 'preserves original record on error' do
        failing_helper = instance_double(Migration::Shared::RedisTempKey)
        allow(failing_helper).to receive(:create_dump_from_hash)
          .and_raise(StandardError.new('Error'))

        encoder = described_class.new(redis_helper: failing_helper, stats: stats)
        record = { key: 'test:1', dump: 'original', v2_fields: { 'id' => '1' } }

        result = encoder.process(record)

        expect(result[:key]).to eq('test:1')
        expect(result[:dump]).to eq('original')
        expect(result[:v2_fields]).to eq({ 'id' => '1' })
      end
    end

    context 'with nil values in fields' do
      it 'filters nil values from hash before encoding' do
        encoder = described_class.new(redis_helper: redis_helper, stats: stats)
        record = {
          key: 'test:1',
          v2_fields: { 'name' => 'Alice', 'empty' => nil, 'value' => 'present' }
        }

        result = encoder.process(record)

        # Decode and verify nil was filtered; values are JSON-encoded
        decoded = redis_helper.restore_and_read_hash(result[:dump], original_key: 'test')
        expect(decoded['name']).to eq('"Alice"')
        expect(decoded['value']).to eq('"present"')
        # Redis hashes don't store nil values, so key should not exist
        expect(decoded).not_to have_key('empty')
      end
    end

    context 'with empty fields hash' do
      # BEHAVIOR CONTRACT: Empty hashes result in encode_error.
      #
      # When v2_fields is empty {}, the encoder:
      # 1. Attempts to create a Redis hash with no fields
      # 2. Redis DUMP returns nil for non-existent keys
      # 3. Base64.strict_encode64(nil) raises TypeError
      # 4. Encoder catches error, attaches :encode_error, increments stat
      #
      # This is intentional: empty records should not be written to Redis.
      # Callers should filter empty records before encoding, or handle
      # records with :encode_error appropriately in destination.

      it 'attaches encode_error for empty hash (documented behavior)' do
        encoder = described_class.new(redis_helper: redis_helper, stats: stats)
        record = { key: 'test:1', v2_fields: {} }

        result = encoder.process(record)

        expect(result[:encode_error]).to be_a(String)
        expect(stats[:encode_errors]).to eq(1)
      end

      it 'preserves original record fields when encode fails' do
        encoder = described_class.new(redis_helper: redis_helper, stats: stats)
        record = { key: 'test:1', dump: 'original', v2_fields: {}, extra: 'preserved' }

        result = encoder.process(record)

        expect(result[:key]).to eq('test:1')
        expect(result[:dump]).to eq('original')
        expect(result[:extra]).to eq('preserved')
      end

      it 'does not increment :encoded stat on empty hash failure' do
        encoder = described_class.new(redis_helper: redis_helper, stats: stats)
        encoder.process({ key: 'test:1', v2_fields: {} })

        expect(stats[:encoded]).to be_nil
        expect(stats[:encode_errors]).to eq(1)
      end
    end

    context 'with hash containing only nil values' do
      # After nil filtering, this becomes an empty hash - same behavior
      it 'treats all-nil-values hash same as empty hash' do
        encoder = described_class.new(redis_helper: redis_helper, stats: stats)
        record = { key: 'test:1', v2_fields: { 'a' => nil, 'b' => nil } }

        result = encoder.process(record)

        expect(result[:encode_error]).to be_a(String)
        expect(stats[:encode_errors]).to eq(1)
      end
    end

    context 'with multiple records' do
      it 'accumulates stats across calls' do
        encoder = described_class.new(redis_helper: redis_helper, stats: stats)

        encoder.process({ key: 'test:1', v2_fields: { 'a' => '1' } })
        encoder.process({ key: 'test:2', v2_fields: { 'b' => '2' } })
        encoder.process({ key: 'test:3' }) # skipped

        expect(stats[:encoded]).to eq(2)
        expect(stats).not_to have_key(:encode_errors)
      end
    end
  end
end
