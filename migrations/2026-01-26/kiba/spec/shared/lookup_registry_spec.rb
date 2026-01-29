# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Migration::Shared::LookupRegistry do
  include TempDirHelper
  include JsonlFileHelper

  let(:temp_dir) { create_temp_dir }
  let(:exports_dir) { temp_dir }
  let(:lookups_dir) { File.join(exports_dir, 'lookups') }

  subject(:registry) { described_class.new(exports_dir: exports_dir) }

  after(:each) do
    FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
  end

  describe '#register and #lookup' do
    it 'registers lookup data and allows lookup' do
      data = { 'user@example.com' => 'uuid-1234' }
      registry.register(:email_to_customer, data, phase: 1)

      result = registry.lookup(:email_to_customer, 'user@example.com')

      expect(result).to eq('uuid-1234')
    end

    it 'returns nil for missing key with default strict: false' do
      registry.register(:email_to_customer, { 'a' => 'b' }, phase: 1)

      result = registry.lookup(:email_to_customer, 'missing@example.com')

      expect(result).to be_nil
    end

    it 'accepts symbol or string lookup names' do
      data = { 'key' => 'value' }
      registry.register('my_lookup', data, phase: 1)

      expect(registry.lookup(:my_lookup, 'key')).to eq('value')
      expect(registry.lookup('my_lookup', 'key')).to eq('value')
    end

    it 'freezes registered data' do
      data = { 'key' => 'value' }
      registry.register(:test_lookup, data, phase: 1)

      # The registered copy should be frozen
      registered = registry.instance_variable_get(:@lookups)[:test_lookup]
      expect(registered).to be_frozen

      # Attempting to modify frozen data raises an error
      expect { registered['new_key'] = 'new_value' }.to raise_error(FrozenError)
    end
  end

  describe '#lookup with strict: true' do
    before do
      registry.register(:email_to_customer, { 'exists@example.com' => 'uuid-1' }, phase: 1)
    end

    it 'returns value for existing key' do
      result = registry.lookup(:email_to_customer, 'exists@example.com', strict: true)

      expect(result).to eq('uuid-1')
    end

    it 'raises LookupKeyNotFoundError for missing key' do
      expect do
        registry.lookup(:email_to_customer, 'missing@example.com', strict: true)
      end.to raise_error(described_class::LookupKeyNotFoundError) do |error|
        expect(error.name).to eq(:email_to_customer)
        expect(error.key).to eq('missing@example.com')
      end
    end

    it 'raises LookupNotLoadedError for unregistered lookup with strict: true' do
      expect do
        registry.lookup(:nonexistent_lookup, 'key', strict: true)
      end.to raise_error(described_class::LookupNotLoadedError) do |error|
        expect(error.name).to eq(:nonexistent_lookup)
      end
    end
  end

  describe '#lookup with strict: false' do
    it 'returns nil for missing key' do
      registry.register(:test, { 'a' => 'b' }, phase: 1)

      expect(registry.lookup(:test, 'missing', strict: false)).to be_nil
    end

    it 'returns nil for unregistered lookup' do
      expect(registry.lookup(:nonexistent, 'key', strict: false)).to be_nil
    end
  end

  describe '#collect and #save' do
    it 'collects key-value pairs' do
      registry.collect(:email_to_customer, 'user1@example.com', 'uuid-1')
      registry.collect(:email_to_customer, 'user2@example.com', 'uuid-2')

      collected = registry.collected(:email_to_customer)

      expect(collected).to eq({
        'user1@example.com' => 'uuid-1',
        'user2@example.com' => 'uuid-2'
      })
    end

    it 'saves collected data to JSON file' do
      registry.collect(:email_to_customer, 'user@example.com', 'uuid-123')

      registry.save(:email_to_customer)

      file_path = File.join(lookups_dir, 'email_to_customer_objid.json')
      expect(File.exist?(file_path)).to be true

      saved_data = JSON.parse(File.read(file_path))
      expect(saved_data).to eq({ 'user@example.com' => 'uuid-123' })
    end

    it 'round-trips data through save and load' do
      original_data = {
        'user1@example.com' => 'uuid-1',
        'user2@example.com' => 'uuid-2'
      }
      original_data.each { |k, v| registry.collect(:email_to_customer, k, v) }
      registry.save(:email_to_customer)

      # Create new registry and load
      new_registry = described_class.new(exports_dir: exports_dir)
      new_registry.load(:email_to_customer)

      expect(new_registry.lookup(:email_to_customer, 'user1@example.com')).to eq('uuid-1')
      expect(new_registry.lookup(:email_to_customer, 'user2@example.com')).to eq('uuid-2')
    end

    it 'allows passing explicit data to save' do
      explicit_data = { 'key1' => 'value1' }

      registry.save(:email_to_customer, data: explicit_data)

      file_path = File.join(lookups_dir, 'email_to_customer_objid.json')
      saved_data = JSON.parse(File.read(file_path))
      expect(saved_data).to eq(explicit_data)
    end

    it 'raises error when saving with no data' do
      expect do
        registry.save(:empty_lookup)
      end.to raise_error(RuntimeError, /No data to save/)
    end
  end

  describe 'phase prerequisite validation' do
    before do
      # Create a phase 2 lookup file
      FileUtils.mkdir_p(lookups_dir)
      File.write(
        File.join(lookups_dir, 'email_to_org_objid.json'),
        JSON.generate({ 'user@example.com' => 'org-uuid' })
      )
    end

    it 'raises PhasePrerequisiteError when requiring phase 2 lookup in phase 1' do
      expect do
        registry.require_lookup(:email_to_org, for_phase: 1)
      end.to raise_error(described_class::PhasePrerequisiteError) do |error|
        expect(error.name).to eq(:email_to_org)
        expect(error.required_by_phase).to eq(1)
        expect(error.produced_in_phase).to eq(2)
      end
    end

    it 'raises PhasePrerequisiteError when phase equals produced phase' do
      expect do
        registry.require_lookup(:email_to_org, for_phase: 2)
      end.to raise_error(described_class::PhasePrerequisiteError)
    end

    it 'allows requiring phase 2 lookup in phase 3' do
      data = registry.require_lookup(:email_to_org, for_phase: 3)

      expect(data).to eq({ 'user@example.com' => 'org-uuid' })
    end

    it 'allows requiring phase 1 lookup in phase 2' do
      FileUtils.mkdir_p(lookups_dir)
      File.write(
        File.join(lookups_dir, 'email_to_customer_objid.json'),
        JSON.generate({ 'user@example.com' => 'cust-uuid' })
      )

      data = registry.require_lookup(:email_to_customer, for_phase: 2)

      expect(data).to eq({ 'user@example.com' => 'cust-uuid' })
    end
  end

  describe '#loaded?' do
    it 'returns false for unloaded lookup' do
      expect(registry.loaded?(:email_to_customer)).to be false
    end

    it 'returns true after registering' do
      registry.register(:email_to_customer, { 'a' => 'b' }, phase: 1)

      expect(registry.loaded?(:email_to_customer)).to be true
    end

    it 'returns true after loading from file' do
      FileUtils.mkdir_p(lookups_dir)
      File.write(
        File.join(lookups_dir, 'email_to_customer_objid.json'),
        JSON.generate({ 'a' => 'b' })
      )
      registry.load(:email_to_customer)

      expect(registry.loaded?(:email_to_customer)).to be true
    end

    it 'accepts symbol or string name' do
      registry.register(:test, {}, phase: 1)

      expect(registry.loaded?('test')).to be true
      expect(registry.loaded?(:test)).to be true
    end
  end

  describe '#clear!' do
    it 'clears all loaded lookups' do
      registry.register(:lookup1, { 'a' => 'b' }, phase: 1)
      registry.register(:lookup2, { 'c' => 'd' }, phase: 2)

      registry.clear!

      expect(registry.loaded?(:lookup1)).to be false
      expect(registry.loaded?(:lookup2)).to be false
    end

    it 'clears collected data' do
      registry.collect(:test, 'key', 'value')

      registry.clear!

      expect(registry.collected(:test)).to be_empty
    end

    it 'clears metadata' do
      registry.register(:test, { 'a' => 'b' }, phase: 1)

      registry.clear!

      metadata = registry.instance_variable_get(:@metadata)
      expect(metadata).to be_empty
    end
  end

  describe 'error classes' do
    describe 'LookupNotFoundError' do
      it 'includes name and file_path' do
        error = described_class::LookupNotFoundError.new(:test_lookup, '/path/to/file.json')

        expect(error.name).to eq(:test_lookup)
        expect(error.file_path).to eq('/path/to/file.json')
        expect(error.message).to include('test_lookup')
        expect(error.message).to include('/path/to/file.json')
      end
    end

    describe 'LookupNotLoadedError' do
      it 'includes name' do
        error = described_class::LookupNotLoadedError.new(:test_lookup)

        expect(error.name).to eq(:test_lookup)
        expect(error.message).to include('test_lookup')
        expect(error.message).to include('not loaded')
      end
    end

    describe 'LookupKeyNotFoundError' do
      it 'includes name and key' do
        error = described_class::LookupKeyNotFoundError.new(:email_lookup, 'missing@example.com')

        expect(error.name).to eq(:email_lookup)
        expect(error.key).to eq('missing@example.com')
        expect(error.message).to include('missing@example.com')
      end
    end

    describe 'PhasePrerequisiteError' do
      it 'includes phase information' do
        error = described_class::PhasePrerequisiteError.new(
          :email_to_org,
          required_by_phase: 1,
          produced_in_phase: 2
        )

        expect(error.name).to eq(:email_to_org)
        expect(error.required_by_phase).to eq(1)
        expect(error.produced_in_phase).to eq(2)
        expect(error.message).to include('phase 1')
        expect(error.message).to include('phase 2')
      end
    end
  end

  describe 'KNOWN_LOOKUPS' do
    it 'defines email_to_customer as phase 1' do
      lookup_meta = described_class::KNOWN_LOOKUPS[:email_to_customer]

      expect(lookup_meta[:phase]).to eq(1)
      expect(lookup_meta[:file]).to eq('email_to_customer_objid.json')
    end

    it 'defines email_to_org as phase 2' do
      lookup_meta = described_class::KNOWN_LOOKUPS[:email_to_org]

      expect(lookup_meta[:phase]).to eq(2)
    end

    it 'defines customer_to_org as phase 2' do
      lookup_meta = described_class::KNOWN_LOOKUPS[:customer_to_org]

      expect(lookup_meta[:phase]).to eq(2)
    end

    it 'defines fqdn_to_domain as phase 3' do
      lookup_meta = described_class::KNOWN_LOOKUPS[:fqdn_to_domain]

      expect(lookup_meta[:phase]).to eq(3)
    end
  end
end
