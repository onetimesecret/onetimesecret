# spec/unit/migrations/unique_index_json_to_raw_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'familia/migration'

require_relative '../../../migrations/2026-06-06/20260606_01_unique_index_json_to_raw'

RSpec.describe Onetime::Migrations::UniqueIndexJsonToRaw do
  let(:redis) { instance_double('Redis') }
  let(:migration) { described_class.new }
  let(:hashkey) do
    instance_double('Familia::HashKey', dbkey: 'custom_domain:display_domain_index')
  end
  let(:descriptor) do
    instance_double(
      'Familia::IndexDescriptor',
      coordinate: 'CustomDomain:display_domain_index',
      index_name: :display_domain_index,
      owner: owner_class,
    )
  end
  let(:owner_class) do
    double('OwnerClass').tap do |klass|
      allow(klass).to receive(:public_send).with(:display_domain_index).and_return(hashkey)
    end
  end

  before do
    allow(migration).to receive(:redis).and_return(redis)
    Familia::Migration.migrations.clear
  end

  describe 'Familia.legacy_json_encoded? detection' do
    it 'detects JSON-encoded string values' do
      expect(Familia.legacy_json_encoded?('"dom_abc123"')).to be true
    end

    it 'rejects raw string values' do
      expect(Familia.legacy_json_encoded?('dom_abc123')).to be false
    end

    it 'rejects empty strings' do
      expect(Familia.legacy_json_encoded?('')).to be false
    end

    it 'rejects nil' do
      expect(Familia.legacy_json_encoded?(nil)).to be false
    end

    it 'rejects non-string values' do
      expect(Familia.legacy_json_encoded?(42)).to be false
    end

    it 'rejects too-short quoted strings' do
      expect(Familia.legacy_json_encoded?('""')).to be false
    end

    it 'handles JSON-encoded UUIDs' do
      expect(Familia.legacy_json_encoded?('"550e8400-e29b-41d4-a716-446655440000"')).to be true
    end
  end

  describe '#migration_needed?' do
    it 'returns true when Familia.stale_indexes returns descriptors' do
      allow(Familia).to receive(:stale_indexes).and_return([descriptor])
      migration.send(:prepare)

      expect(migration.migration_needed?).to be true
    end

    it 'returns false when no stale indexes found' do
      allow(Familia).to receive(:stale_indexes).and_return([])
      migration.send(:prepare)

      expect(migration.migration_needed?).to be false
    end
  end

  describe '#convert_index' do
    before do
      allow(Familia).to receive(:stale_indexes).and_return([descriptor])
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

      migration.send(:convert_index, descriptor)

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

      migration.send(:convert_index, descriptor)

      expect(migration).to have_received(:track_stat).with(:entries_converted).once
    end

    it 'skips already-raw values' do
      allow(migration).to receive(:dry_run?).and_return(false)
      allow(migration).to receive(:info)
      entries = [['example.com', 'dom_abc123']]
      allow(redis).to receive(:hscan_each)
        .with('custom_domain:display_domain_index', count: 100)
        .and_return(entries.each)

      migration.send(:convert_index, descriptor)

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
