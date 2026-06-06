# spec/unit/migrations/unique_index_json_to_raw_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'familia/migration'

require_relative '../../../migrations/2026-06-06/20260606_01_unique_index_json_to_raw'

RSpec.describe Onetime::Migrations::UniqueIndexJsonToRaw do
  let(:redis) { instance_double('Redis') }
  let(:migration) { described_class.new }

  before do
    allow(migration).to receive(:redis).and_return(redis)
    Familia::Migration.migrations.clear
  end

  describe '#json_encoded_string?' do
    it 'detects JSON-encoded string values' do
      expect(migration.send(:json_encoded_string?, '"dom_abc123"')).to be true
    end

    it 'rejects raw string values' do
      expect(migration.send(:json_encoded_string?, 'dom_abc123')).to be false
    end

    it 'rejects empty strings' do
      expect(migration.send(:json_encoded_string?, '')).to be false
    end

    it 'rejects nil' do
      expect(migration.send(:json_encoded_string?, nil)).to be false
    end

    it 'rejects non-string values' do
      expect(migration.send(:json_encoded_string?, 42)).to be false
    end

    it 'rejects strings that start but do not end with quote' do
      expect(migration.send(:json_encoded_string?, '"partial')).to be false
    end

    it 'handles JSON-encoded UUIDs' do
      expect(migration.send(:json_encoded_string?, '"550e8400-e29b-41d4-a716-446655440000"')).to be true
    end
  end

  describe '#discover_index_keys' do
    before do
      migration.send(:prepare)
    end

    it 'includes existing global index keys' do
      allow(redis).to receive(:exists?).and_return(false)
      allow(redis).to receive(:exists?).with('custom_domain:display_domain_index').and_return(true)
      allow(redis).to receive(:exists?).with('customer:email_index').and_return(true)
      allow(redis).to receive(:scan_each).and_return([].each)

      keys = migration.send(:discover_index_keys)
      expect(keys).to include('custom_domain:display_domain_index')
      expect(keys).to include('customer:email_index')
    end

    it 'excludes non-existent global index keys' do
      allow(redis).to receive(:exists?).and_return(false)
      allow(redis).to receive(:scan_each).and_return([].each)

      keys = migration.send(:discover_index_keys)
      expect(keys).to be_empty
    end

    it 'discovers org-scoped index keys via SCAN' do
      allow(redis).to receive(:exists?).and_return(false)
      scoped_keys = ['organization:org1:email_index', 'organization:org2:email_index']
      allow(redis).to receive(:scan_each).with(match: 'organization:*:email_index').and_return(scoped_keys.each)

      keys = migration.send(:discover_index_keys)
      expect(keys).to eq(scoped_keys)
    end
  end

  describe '#migration_needed?' do
    before do
      migration.send(:prepare)
    end

    it 'returns true when JSON-encoded values exist' do
      allow(redis).to receive(:exists?).and_return(false)
      allow(redis).to receive(:exists?).with('customer:email_index').and_return(true)
      allow(redis).to receive(:scan_each).and_return([].each)
      allow(redis).to receive(:hscan_each)
        .with('customer:email_index', count: 100)
        .and_yield('user@example.com', '"cust_abc123"')

      expect(migration.migration_needed?).to be true
    end

    it 'returns false when all values are raw' do
      allow(redis).to receive(:exists?).and_return(false)
      allow(redis).to receive(:exists?).with('customer:email_index').and_return(true)
      allow(redis).to receive(:scan_each).and_return([].each)
      allow(redis).to receive(:hscan_each)
        .with('customer:email_index', count: 100)
        .and_return([['user@example.com', 'cust_abc123']].each)

      expect(migration.migration_needed?).to be false
    end

    it 'returns false when no index keys exist' do
      allow(redis).to receive(:exists?).and_return(false)
      allow(redis).to receive(:scan_each).and_return([].each)

      expect(migration.migration_needed?).to be false
    end
  end

  describe '#convert_index' do
    before do
      migration.send(:prepare)
      allow(migration).to receive(:track_stat)
    end

    it 'rewrites JSON-encoded values as raw strings in execute mode' do
      allow(migration).to receive(:dry_run?).and_return(false)
      allow(migration).to receive(:info)
      entries = [
        ['example.com', '"dom_abc123"'],
        ['other.com', 'dom_def456'],
      ]
      allow(redis).to receive(:hscan_each)
        .with('custom_domain:display_domain_index', count: 100)
        .and_return(entries.each)
      allow(redis).to receive(:hset)

      migration.send(:convert_index, 'custom_domain:display_domain_index')

      expect(redis).to have_received(:hset).with('custom_domain:display_domain_index', 'example.com', 'dom_abc123')
      expect(migration).to have_received(:track_stat).with(:entries_converted).once
      expect(migration).to have_received(:track_stat).with(:entries_already_raw).once
    end

    it 'does not write in dry-run mode' do
      allow(migration).to receive(:dry_run?).and_return(true)
      allow(migration).to receive(:info)
      entries = [['example.com', '"dom_abc123"']]
      allow(redis).to receive(:hscan_each)
        .with('custom_domain:display_domain_index', count: 100)
        .and_return(entries.each)

      migration.send(:convert_index, 'custom_domain:display_domain_index')

      expect(migration).to have_received(:track_stat).with(:entries_converted).once
    end

    it 'skips already-raw values' do
      allow(migration).to receive(:dry_run?).and_return(false)
      allow(migration).to receive(:info)
      entries = [['example.com', 'dom_abc123']]
      allow(redis).to receive(:hscan_each)
        .with('custom_domain:display_domain_index', count: 100)
        .and_return(entries.each)

      migration.send(:convert_index, 'custom_domain:display_domain_index')

      expect(migration).not_to have_received(:track_stat).with(:entries_converted)
      expect(migration).to have_received(:track_stat).with(:entries_already_raw).once
    end
  end

  describe 'migration metadata' do
    it 'has the expected migration_id' do
      expect(described_class.migration_id).to eq('20260606_01_unique_index_json_to_raw')
    end

    it 'has no dependencies' do
      expect(described_class.dependencies).to be_empty
    end
  end
end
