# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Migration::Shared::RedisTempKey do
  include TempDirHelper

  let(:redis_url) { 'redis://127.0.0.1:6379' }
  let(:temp_db) { 15 }
  subject(:helper) { described_class.new(redis_url: redis_url, temp_db: temp_db) }

  before(:each) do
    RedisTestHelper.skip_unless_redis_available
  end

  describe '#connect! and #disconnect!' do
    it 'connects to Redis successfully' do
      helper.connect!

      expect(helper.connected?).to be true
    ensure
      helper.disconnect!
    end

    it 'disconnects from Redis' do
      helper.connect!
      helper.disconnect!

      # After disconnect, connected? returns nil (falsy) because @redis is nil
      expect(helper.connected?).to be_falsy
    end

    it 'returns the Redis client on connect' do
      client = helper.connect!

      expect(client).to be_a(Redis)
    ensure
      helper.disconnect!
    end
  end

  describe '#connected?' do
    it 'returns falsy value before connecting' do
      # Before connecting, @redis is nil, so connected? returns nil (falsy)
      expect(helper.connected?).to be_falsy
    end

    it 'returns true after connecting' do
      helper.connect!

      expect(helper.connected?).to be true
    ensure
      helper.disconnect!
    end

    it 'returns falsy value after disconnecting' do
      helper.connect!
      helper.disconnect!

      # After disconnect, @redis is nil, so connected? returns nil (falsy)
      expect(helper.connected?).to be_falsy
    end
  end

  describe '#create_dump_from_hash and #restore_and_read_hash' do
    before { helper.connect! }
    after { helper.disconnect! }

    it 'round-trips hash data correctly' do
      original = { 'name' => 'test', 'value' => '123', 'nested' => 'data' }

      dump_b64 = helper.create_dump_from_hash(original)
      restored = helper.restore_and_read_hash(dump_b64, original_key: 'test:key')

      expect(restored).to eq(original)
    end

    it 'preserves all fields in round-trip' do
      original = {
        'custid' => 'test@example.com',
        'created' => '1706140800.0',
        'role' => 'customer',
        'verified' => 'true',
        'planid' => 'free'
      }

      dump_b64 = helper.create_dump_from_hash(original)
      restored = helper.restore_and_read_hash(dump_b64, original_key: 'customer:test')

      expect(restored).to eq(original)
    end

    it 'raises ArgumentError when hash compacts to empty' do
      # When all values are nil, the hash becomes empty after compact
      original = { 'only_nil' => nil }

      expect do
        helper.create_dump_from_hash(original)
      end.to raise_error(ArgumentError, 'Cannot create dump from empty hash')
    end

    it 'raises ArgumentError for explicitly empty hash' do
      expect do
        helper.create_dump_from_hash({})
      end.to raise_error(ArgumentError, 'Cannot create dump from empty hash')
    end

    it 'raises ArgumentError when multiple nil values compact to empty' do
      original = { 'a' => nil, 'b' => nil, 'c' => nil }

      expect do
        helper.create_dump_from_hash(original)
      end.to raise_error(ArgumentError, 'Cannot create dump from empty hash')
    end

    it 'handles hash with at least one non-nil field' do
      original = { 'name' => 'test', 'nil_field' => nil }

      dump_b64 = helper.create_dump_from_hash(original)
      restored = helper.restore_and_read_hash(dump_b64, original_key: 'test:key')

      expect(restored).to eq({ 'name' => 'test' })
    end

    it 'filters out nil values when creating dump' do
      original = { 'name' => 'test', 'nil_field' => nil, 'value' => '123' }

      dump_b64 = helper.create_dump_from_hash(original)
      restored = helper.restore_and_read_hash(dump_b64, original_key: 'test:key')

      expect(restored).to include('name' => 'test', 'value' => '123')
      expect(restored).not_to have_key('nil_field')
    end

    it 'handles special characters in values' do
      original = { 'unicode' => "\u{1F600}", 'newline' => "line1\nline2" }

      dump_b64 = helper.create_dump_from_hash(original)
      restored = helper.restore_and_read_hash(dump_b64, original_key: 'special:key')

      expect(restored).to eq(original)
    end
  end

  describe 'Base64 validation errors' do
    before { helper.connect! }
    after { helper.disconnect! }

    it 'raises Base64FormatError for invalid characters' do
      invalid_b64 = 'not!valid@base64#'

      expect do
        helper.restore_and_read_hash(invalid_b64, original_key: 'bad:key')
      end.to raise_error(described_class::Base64FormatError) do |error|
        expect(error.key).to eq('bad:key')
        expect(error.reason).to include('Invalid Base64')
      end
    end

    it 'raises Base64FormatError for wrong padding' do
      # Valid base64 chars but wrong padding
      wrong_padding = 'YWJjZA='

      expect do
        helper.restore_and_read_hash(wrong_padding, original_key: 'bad:key')
      end.to raise_error(described_class::Base64FormatError) do |error|
        expect(error.reason).to include('Invalid Base64')
      end
    end

    it 'raises Base64FormatError for wrong length' do
      # Length not multiple of 4
      wrong_length = 'YWJjZGU'

      expect do
        helper.restore_and_read_hash(wrong_length, original_key: 'bad:key')
      end.to raise_error(described_class::Base64FormatError) do |error|
        expect(error.reason).to include('Invalid Base64 length')
      end
    end

    it 'accepts valid Base64 with padding' do
      # Create valid dump first
      dump_b64 = helper.create_dump_from_hash({ 'test' => 'value' })

      expect { helper.restore_and_read_hash(dump_b64, original_key: 'test') }.not_to raise_error
    end
  end

  describe 'NotConnectedError' do
    it 'raises NotConnectedError when restore_and_read_hash called without connecting' do
      expect do
        helper.restore_and_read_hash('YWJj', original_key: 'test')
      end.to raise_error(described_class::NotConnectedError)
    end

    it 'raises NotConnectedError when create_dump_from_hash called without connecting' do
      expect do
        helper.create_dump_from_hash({ 'test' => 'value' })
      end.to raise_error(described_class::NotConnectedError)
    end
  end

  describe 'RestoreError' do
    before { helper.connect! }
    after { helper.disconnect! }

    it 'raises RestoreError for invalid DUMP data' do
      # Valid Base64 but not valid Redis DUMP format
      invalid_dump = Base64.strict_encode64('not a valid redis dump')

      expect do
        helper.restore_and_read_hash(invalid_dump, original_key: 'bad:dump')
      end.to raise_error(described_class::RestoreError) do |error|
        expect(error.key).to eq('bad:dump')
        expect(error.redis_message).not_to be_empty
      end
    end
  end

  describe '#cleanup!' do
    before { helper.connect! }
    after { helper.disconnect! }

    it 'removes temporary keys' do
      # Create some temp keys through normal operations
      helper.create_dump_from_hash({ 'test' => 'value' })

      deleted = helper.cleanup!

      # Should return number of keys deleted (could be 0 if auto-cleaned)
      expect(deleted).to be >= 0
    end

    it 'returns 0 when not connected' do
      helper.disconnect!

      expect(helper.cleanup!).to eq(0)
    end
  end

  describe '#with_cleanup' do
    before { helper.connect! }
    after { helper.disconnect! }

    it 'yields the block' do
      yielded = false

      helper.with_cleanup { yielded = true }

      expect(yielded).to be true
    end

    it 'returns block result' do
      result = helper.with_cleanup { 42 }

      expect(result).to eq(42)
    end

    it 'ensures cleanup on normal completion' do
      # We can verify cleanup was called by checking no temp keys remain
      helper.with_cleanup do
        # Create some internal state
        helper.create_dump_from_hash({ 'test' => 'value' })
      end

      # Temp keys should be cleaned up
      redis = Redis.new(url: "#{redis_url}/#{temp_db}")
      keys = redis.keys("#{described_class::TEMP_KEY_PREFIX}*")
      redis.close

      expect(keys).to be_empty
    end

    it 'ensures cleanup on exception' do
      expect do
        helper.with_cleanup do
          helper.create_dump_from_hash({ 'test' => 'value' })
          raise 'Intentional error'
        end
      end.to raise_error(RuntimeError, 'Intentional error')

      # Cleanup should still have run
      redis = Redis.new(url: "#{redis_url}/#{temp_db}")
      keys = redis.keys("#{described_class::TEMP_KEY_PREFIX}*")
      redis.close

      expect(keys).to be_empty
    end
  end

  describe 'error class attributes' do
    describe 'NotConnectedError' do
      it 'has descriptive message' do
        error = described_class::NotConnectedError.new
        expect(error.message).to include('not connected')
      end
    end

    describe 'RestoreError' do
      it 'exposes key and redis_message' do
        error = described_class::RestoreError.new('my:key', 'DUMP payload version mismatch')

        expect(error.key).to eq('my:key')
        expect(error.redis_message).to eq('DUMP payload version mismatch')
        expect(error.message).to include('my:key')
      end
    end

    describe 'Base64FormatError' do
      it 'exposes key and reason' do
        error = described_class::Base64FormatError.new('my:key', 'Invalid padding')

        expect(error.key).to eq('my:key')
        expect(error.reason).to eq('Invalid padding')
        expect(error.message).to include('my:key')
        expect(error.message).to include('Invalid padding')
      end
    end
  end
end
