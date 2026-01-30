# migrations/2026-01-28/spec/transforms/redis_dump_decoder_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Migration::Transforms::RedisDumpDecoder do
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
      decoder = described_class.new(redis_helper: redis_helper, stats: stats)

      expect(decoder.redis_helper).to be(redis_helper)
    end
  end

  describe '#process' do
    context 'with valid DUMP data' do
      let(:valid_dump) do
        # Create a dump simulating v1 data (no JSON serialization) for decoder testing.
        # This reflects real v1 Redis data which has plain string values.
        redis_helper.create_dump_from_hash(
          { 'name' => 'Alice', 'email' => 'alice@example.com' },
          serialize_values: false
        )
      end

      it 'decodes valid DUMP and adds :fields hash to record' do
        decoder = described_class.new(redis_helper: redis_helper, stats: stats)
        record = { key: 'customer:alice@example.com:object', dump: valid_dump, type: 'hash' }

        result = decoder.process(record)

        expect(result[:fields]).to be_a(Hash)
        expect(result[:fields]['name']).to eq('Alice')
        expect(result[:fields]['email']).to eq('alice@example.com')
      end

      it 'preserves other record fields' do
        decoder = described_class.new(redis_helper: redis_helper, stats: stats)
        record = {
          key: 'customer:alice@example.com:object',
          dump: valid_dump,
          type: 'hash',
          ttl_ms: -1,
          db: 0,
          extra_field: 'preserved'
        }

        result = decoder.process(record)

        expect(result[:key]).to eq('customer:alice@example.com:object')
        expect(result[:type]).to eq('hash')
        expect(result[:ttl_ms]).to eq(-1)
        expect(result[:db]).to eq(0)
        expect(result[:extra_field]).to eq('preserved')
        expect(result[:dump]).to eq(valid_dump)
      end

      it 'increments :decoded stat on success' do
        decoder = described_class.new(redis_helper: redis_helper, stats: stats)
        record = { key: 'test:1', dump: valid_dump }

        decoder.process(record)

        expect(stats[:decoded]).to eq(1)
      end
    end

    context 'with missing :dump field' do
      it 'passes record through unchanged' do
        decoder = described_class.new(redis_helper: redis_helper, stats: stats)
        record = { key: 'test:1', type: 'hash' }

        result = decoder.process(record)

        expect(result).to eq(record)
        expect(result).not_to have_key(:fields)
      end

      it 'does not modify stats' do
        decoder = described_class.new(redis_helper: redis_helper, stats: stats)
        record = { key: 'test:1' }

        decoder.process(record)

        expect(stats).to be_empty
      end
    end

    context 'with nil :dump value' do
      it 'passes record through unchanged' do
        decoder = described_class.new(redis_helper: redis_helper, stats: stats)
        record = { key: 'test:1', dump: nil }

        result = decoder.process(record)

        expect(result).to eq(record)
        expect(result).not_to have_key(:fields)
      end
    end

    context 'with decode error (RestoreError)' do
      # Use a mock helper that raises RestoreError since the decoder only catches that type
      let(:failing_helper) do
        helper = instance_double(Migration::Shared::RedisTempKey)
        allow(helper).to receive(:restore_and_read_hash)
          .and_raise(Migration::Shared::RedisTempKey::RestoreError.new('test:1', 'DUMP payload version or checksum are wrong'))
        helper
      end

      it 'attaches :decode_error to record and continues' do
        decoder = described_class.new(redis_helper: failing_helper, stats: stats)
        record = { key: 'test:1', dump: 'YWJjZGVm' } # valid base64

        result = decoder.process(record)

        expect(result).to be_a(Hash)
        expect(result[:decode_error]).to be_a(String)
        expect(result[:decode_error]).to include('DUMP payload')
      end

      it 'increments :decode_errors stat on failure' do
        decoder = described_class.new(redis_helper: failing_helper, stats: stats)
        record = { key: 'test:1', dump: 'YWJjZGVm' }

        decoder.process(record)

        expect(stats[:decode_errors]).to eq(1)
      end

      it 'does not add :fields on error' do
        decoder = described_class.new(redis_helper: failing_helper, stats: stats)
        record = { key: 'test:1', dump: 'YWJjZGVm' }

        result = decoder.process(record)

        expect(result).not_to have_key(:fields)
      end
    end

    context 'with multiple records' do
      it 'accumulates stats across multiple calls' do
        dump1 = redis_helper.create_dump_from_hash({ 'id' => '1' })
        dump2 = redis_helper.create_dump_from_hash({ 'id' => '2' })

        # Create a mixed helper that succeeds twice then fails
        call_count = 0
        mixed_helper = instance_double(Migration::Shared::RedisTempKey)
        allow(mixed_helper).to receive(:restore_and_read_hash) do |dump_b64, **_opts|
          call_count += 1
          if call_count <= 2
            redis_helper.restore_and_read_hash(dump_b64, original_key: "test:#{call_count}")
          else
            raise Migration::Shared::RedisTempKey::RestoreError.new('test:3', 'invalid')
          end
        end

        decoder = described_class.new(redis_helper: mixed_helper, stats: stats)

        decoder.process({ key: 'test:1', dump: dump1 })
        decoder.process({ key: 'test:2', dump: dump2 })
        decoder.process({ key: 'test:3', dump: 'YWJjZA==' })

        expect(stats[:decoded]).to eq(2)
        expect(stats[:decode_errors]).to eq(1)
      end
    end
  end
end
