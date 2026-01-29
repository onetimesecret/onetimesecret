# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Migration::Shared::UuidV7Generator do
  subject(:generator) { described_class.new }

  describe '#generate_from_timestamp' do
    let(:timestamp) { 1706140800 } # 2024-01-25 00:00:00 UTC

    it 'generates valid UUIDv7 format (8-4-4-4-12 hex pattern)' do
      uuid = generator.generate_from_timestamp(timestamp)

      expect(uuid).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    end

    it 'sets version bits (bits 48-51) to 0111 for version 7' do
      uuid = generator.generate_from_timestamp(timestamp)
      parts = uuid.split('-')
      version_nibble = parts[2][0]

      expect(version_nibble).to eq('7')
    end

    it 'sets variant bits (bits 64-65) to 10 (RFC 4122 variant)' do
      uuid = generator.generate_from_timestamp(timestamp)
      parts = uuid.split('-')
      variant_byte = parts[3][0, 2].to_i(16)

      # Bits 64-65 should be 10 in binary, meaning byte should be 0x80-0xBF
      expect(variant_byte).to be_between(0x80, 0xBF)
    end

    it 'encodes timestamp in first 48 bits' do
      uuid = generator.generate_from_timestamp(timestamp)
      parts = uuid.split('-')

      # Extract first 48 bits (time_hi + time_mid)
      time_hex = parts[0] + parts[1]
      encoded_ms = time_hex.to_i(16)

      # Expected milliseconds
      expected_ms = (timestamp * 1000)

      expect(encoded_ms).to eq(expected_ms)
    end

    it 'produces different UUIDs for same timestamp due to random bits' do
      uuid1 = generator.generate_from_timestamp(timestamp)
      uuid2 = generator.generate_from_timestamp(timestamp)

      expect(uuid1).not_to eq(uuid2)
    end

    context 'with epoch 0' do
      let(:timestamp) { 0 }

      it 'generates valid UUID with zero timestamp' do
        uuid = generator.generate_from_timestamp(timestamp)

        expect(uuid).to match(/^00000000-0000-7/)
      end

      it 'still has correct version and variant bits' do
        uuid = generator.generate_from_timestamp(timestamp)
        parts = uuid.split('-')

        expect(parts[2][0]).to eq('7')
        expect(parts[3][0, 2].to_i(16)).to be_between(0x80, 0xBF)
      end
    end

    context 'with very large timestamp' do
      # Year 3000 approximately
      let(:timestamp) { 32503680000 }

      it 'generates valid UUID' do
        uuid = generator.generate_from_timestamp(timestamp)

        expect(uuid).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
      end

      it 'encodes the large timestamp correctly' do
        uuid = generator.generate_from_timestamp(timestamp)
        parts = uuid.split('-')
        time_hex = parts[0] + parts[1]
        encoded_ms = time_hex.to_i(16)

        expect(encoded_ms).to eq(timestamp * 1000)
      end
    end

    context 'with float timestamp' do
      let(:timestamp) { 1706140800.123 }

      it 'converts to milliseconds and generates valid UUID' do
        uuid = generator.generate_from_timestamp(timestamp)

        expect(uuid).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
      end
    end
  end

  describe '#derive_extid' do
    let(:uuid_string) { '0194a700-1234-7abc-8def-0123456789ab' }
    let(:prefix) { 'ur' }

    it 'produces deterministic extid from same UUID' do
      extid1 = generator.derive_extid(uuid_string, prefix: prefix)
      extid2 = generator.derive_extid(uuid_string, prefix: prefix)

      expect(extid1).to eq(extid2)
    end

    it 'applies the prefix correctly' do
      extid = generator.derive_extid(uuid_string, prefix: 'ur')

      expect(extid).to start_with('ur')
    end

    it 'produces different extids for different UUIDs' do
      uuid2 = '0194a700-5678-7abc-8def-0123456789ab'
      extid1 = generator.derive_extid(uuid_string, prefix: prefix)
      extid2 = generator.derive_extid(uuid2, prefix: prefix)

      expect(extid1).not_to eq(extid2)
    end

    it 'handles UUIDs without hyphens' do
      uuid_no_hyphens = uuid_string.delete('-')
      extid_with = generator.derive_extid(uuid_string, prefix: prefix)
      extid_without = generator.derive_extid(uuid_no_hyphens, prefix: prefix)

      expect(extid_with).to eq(extid_without)
    end

    it 'produces extid with prefix plus 25 base36 characters' do
      extid = generator.derive_extid(uuid_string, prefix: prefix)

      # prefix length (2) + 25 characters
      expect(extid.length).to eq(27)
      expect(extid[2..]).to match(/^[0-9a-z]+$/)
    end

    context 'with different prefixes' do
      it 'applies customer prefix "ur"' do
        extid = generator.derive_extid(uuid_string, prefix: 'ur')
        expect(extid).to start_with('ur')
      end

      it 'applies custom_domain prefix "cd"' do
        extid = generator.derive_extid(uuid_string, prefix: 'cd')
        expect(extid).to start_with('cd')
      end

      it 'applies organization prefix "on"' do
        extid = generator.derive_extid(uuid_string, prefix: 'on')
        expect(extid).to start_with('on')
      end
    end
  end

  describe '#generate_identifiers' do
    let(:timestamp) { 1706140800 }
    let(:prefix) { 'ur' }

    it 'returns an array with [objid, extid]' do
      result = generator.generate_identifiers(timestamp, prefix: prefix)

      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
    end

    it 'generates valid objid as first element' do
      objid, = generator.generate_identifiers(timestamp, prefix: prefix)

      expect(objid).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
    end

    it 'generates valid extid as second element' do
      _, extid = generator.generate_identifiers(timestamp, prefix: prefix)

      expect(extid).to start_with(prefix)
      expect(extid.length).to eq(27)
    end

    it 'derives extid from the generated objid' do
      objid, extid = generator.generate_identifiers(timestamp, prefix: prefix)
      expected_extid = generator.derive_extid(objid, prefix: prefix)

      expect(extid).to eq(expected_extid)
    end
  end
end
