# migrations/2026-01-28/spec/destinations/composite_destination_spec.rb
#
# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Migration::Destinations::CompositeDestination do
  include TempDirHelper
  include JsonlFileHelper

  let(:temp_dir) { create_temp_dir }
  let(:jsonl_file) { File.join(temp_dir, 'output.jsonl') }
  let(:lookup_file) { File.join(temp_dir, 'lookup.json') }

  after do
    FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
  end

  describe '#initialize' do
    it 'initializes all destinations from config array' do
      dest = described_class.new(
        destinations: [
          [Migration::Destinations::JsonlDestination, { file: jsonl_file }],
          [Migration::Destinations::LookupDestination, {
            file: lookup_file,
            key_field: :email,
            value_field: :objid,
          }],
        ]
      )

      expect(dest.destinations.size).to eq(2)
      expect(dest.destinations[0]).to be_a(Migration::Destinations::JsonlDestination)
      expect(dest.destinations[1]).to be_a(Migration::Destinations::LookupDestination)
    end

    it 'preserves order of destinations' do
      dest = described_class.new(
        destinations: [
          [Migration::Destinations::LookupDestination, {
            file: lookup_file,
            key_field: :email,
            value_field: :objid,
          }],
          [Migration::Destinations::JsonlDestination, { file: jsonl_file }],
        ]
      )

      expect(dest.destinations[0]).to be_a(Migration::Destinations::LookupDestination)
      expect(dest.destinations[1]).to be_a(Migration::Destinations::JsonlDestination)
    end

    it 'passes options to destination constructors' do
      dest = described_class.new(
        destinations: [
          [Migration::Destinations::JsonlDestination, {
            file: jsonl_file,
            exclude_fields: %i[internal secret],
          }],
        ]
      )

      jsonl_dest = dest.destinations.first
      expect(jsonl_dest.file).to eq(jsonl_file)
      expect(jsonl_dest.exclude_fields).to eq(%i[internal secret])
    end

    it 'works with empty destinations array' do
      dest = described_class.new(destinations: [])
      expect(dest.destinations).to eq([])
    end
  end

  describe '#write' do
    it 'fans out to all destinations' do
      dest = described_class.new(
        destinations: [
          [Migration::Destinations::JsonlDestination, { file: jsonl_file }],
          [Migration::Destinations::LookupDestination, {
            file: lookup_file,
            key_field: :email,
            value_field: :objid,
          }],
        ]
      )

      record = { email: 'test@example.com', objid: 'uuid-123', type: 'hash' }
      dest.write(record)
      dest.close

      # Check JSONL destination got the record
      jsonl_records = read_jsonl(jsonl_file)
      expect(jsonl_records.size).to eq(1)
      expect(jsonl_records.first[:email]).to eq('test@example.com')

      # Check Lookup destination got the record
      lookup_data = read_json(lookup_file)
      expect(lookup_data).to eq({ 'test@example.com' => 'uuid-123' })
    end

    it 'writes multiple records to all destinations' do
      dest = described_class.new(
        destinations: [
          [Migration::Destinations::JsonlDestination, { file: jsonl_file }],
          [Migration::Destinations::LookupDestination, {
            file: lookup_file,
            key_field: :email,
            value_field: :objid,
          }],
        ]
      )

      records = [
        { email: 'a@test.com', objid: 'uuid-1', data: 'first' },
        { email: 'b@test.com', objid: 'uuid-2', data: 'second' },
        { email: 'c@test.com', objid: 'uuid-3', data: 'third' },
      ]

      records.each { |r| dest.write(r) }
      dest.close

      jsonl_records = read_jsonl(jsonl_file)
      expect(jsonl_records.size).to eq(3)

      lookup_data = read_json(lookup_file)
      expect(lookup_data.keys.size).to eq(3)
      expect(lookup_data['a@test.com']).to eq('uuid-1')
    end

    context 'error handling' do
      # Create a destination class that raises on write
      let(:error_destination_class) do
        Class.new do
          attr_reader :write_calls

          def initialize(**)
            @write_calls = 0
          end

          def write(_record)
            @write_calls += 1
            raise 'Simulated write error' if @write_calls == 1
          end

          def close; end
        end
      end

      it 'error in one destination propagates (does not continue to others)' do
        # Note: The current implementation does NOT rescue errors
        # So an error in one destination will prevent others from receiving the write
        # This test documents the actual behavior

        # We need to verify the behavior: does it rescue or propagate?
        # Based on the implementation: @destinations.each { |dest| dest.write(record) }
        # There's no rescue, so errors propagate

        # Create a mock destination that tracks calls
        mock_dest1 = instance_double('Destination')
        mock_dest2 = instance_double('Destination')

        allow(mock_dest1).to receive(:write).and_raise('Error in first dest')
        # mock_dest2.write should never be called because error propagates

        dest = described_class.new(destinations: [])
        dest.instance_variable_set(:@destinations, [mock_dest1, mock_dest2])

        expect { dest.write({ key: 'test' }) }.to raise_error('Error in first dest')
      end
    end
  end

  describe '#close' do
    it 'fans out to all destinations' do
      dest = described_class.new(
        destinations: [
          [Migration::Destinations::JsonlDestination, { file: jsonl_file }],
          [Migration::Destinations::LookupDestination, {
            file: lookup_file,
            key_field: :email,
            value_field: :objid,
          }],
        ]
      )

      # Write some data
      dest.write({ email: 'test@example.com', objid: 'uuid-123' })

      # Verify destinations are in expected state before close
      jsonl_dest = dest.destinations[0]
      lookup_dest = dest.destinations[1]

      expect(jsonl_dest.count).to eq(1)
      expect(lookup_dest.count).to eq(1)

      dest.close

      # After close, files should be written
      expect(File.exist?(jsonl_file)).to be true
      expect(File.exist?(lookup_file)).to be true
    end

    it 'can be called on empty composite' do
      dest = described_class.new(destinations: [])
      expect { dest.close }.not_to raise_error
    end
  end

  describe '#find_destination' do
    let(:dest) do
      described_class.new(
        destinations: [
          [Migration::Destinations::JsonlDestination, { file: jsonl_file }],
          [Migration::Destinations::LookupDestination, {
            file: lookup_file,
            key_field: :email,
            value_field: :objid,
          }],
        ]
      )
    end

    after { dest.close }

    it 'returns correct destination instance by class' do
      found = dest.find_destination(Migration::Destinations::JsonlDestination)

      expect(found).to be_a(Migration::Destinations::JsonlDestination)
      expect(found.file).to eq(jsonl_file)
    end

    it 'returns nil for unknown class' do
      # Using a class that's not in the composite
      found = dest.find_destination(String)

      expect(found).to be_nil
    end

    it 'returns first match when multiple of same type' do
      file2 = File.join(temp_dir, 'output2.jsonl')
      multi_dest = described_class.new(
        destinations: [
          [Migration::Destinations::JsonlDestination, { file: jsonl_file }],
          [Migration::Destinations::JsonlDestination, { file: file2 }],
        ]
      )

      found = multi_dest.find_destination(Migration::Destinations::JsonlDestination)

      expect(found.file).to eq(jsonl_file) # First one
      multi_dest.close
    end
  end

  describe 'integration with real destinations' do
    it 'works with full pipeline pattern' do
      stats = { lookup_entries: 0 }

      dest = described_class.new(
        destinations: [
          [Migration::Destinations::JsonlDestination, {
            file: jsonl_file,
            exclude_fields: %i[fields v2_fields],
          }],
          [Migration::Destinations::LookupDestination, {
            file: lookup_file,
            key_field: :v1_custid,
            value_field: :objid,
            phase: 1,
            stats: stats,
          }],
        ]
      )

      # Simulate transformed records
      records = [
        {
          key: 'customer:uuid-1:object',
          type: 'hash',
          objid: 'uuid-1',
          v1_custid: 'alice@example.com',
          fields: { 'custid' => 'alice@example.com' },
          v2_fields: { 'objid' => 'uuid-1', 'custid' => 'uuid-1' },
        },
        {
          key: 'customer:uuid-2:object',
          type: 'hash',
          objid: 'uuid-2',
          v1_custid: 'bob@example.com',
          fields: { 'custid' => 'bob@example.com' },
          v2_fields: { 'objid' => 'uuid-2', 'custid' => 'uuid-2' },
        },
      ]

      records.each { |r| dest.write(r) }
      dest.close

      # Verify JSONL output excludes internal fields
      jsonl_records = read_jsonl(jsonl_file)
      expect(jsonl_records.size).to eq(2)
      expect(jsonl_records.first).not_to have_key(:fields)
      expect(jsonl_records.first).not_to have_key(:v2_fields)
      expect(jsonl_records.first[:objid]).to eq('uuid-1')

      # Verify lookup file
      lookup_data = read_json(lookup_file)
      expect(lookup_data['alice@example.com']).to eq('uuid-1')
      expect(lookup_data['bob@example.com']).to eq('uuid-2')

      # Verify stats updated
      expect(stats[:lookup_entries]).to eq(2)
    end
  end

  describe 'close error handling' do
    context 'when one destination fails on close' do
      # Create a destination class that raises on close
      let(:failing_destination_class) do
        Class.new do
          def initialize(**); end
          def write(_record); end

          def close
            raise 'Simulated close error'
          end
        end
      end

      it 'propagates error from first failing destination' do
        dest = described_class.new(destinations: [])
        mock_dest1 = instance_double('Destination')
        mock_dest2 = instance_double('Destination')

        allow(mock_dest1).to receive(:close).and_raise('Close error in dest1')
        # mock_dest2.close never called because error propagates

        dest.instance_variable_set(:@destinations, [mock_dest1, mock_dest2])

        expect { dest.close }.to raise_error('Close error in dest1')
      end

      it 'calls close on all destinations before first error when they succeed' do
        dest = described_class.new(destinations: [])
        mock_dest1 = instance_double('Destination')
        mock_dest2 = instance_double('Destination')
        mock_dest3 = instance_double('Destination')

        allow(mock_dest1).to receive(:close)
        allow(mock_dest2).to receive(:close).and_raise('Close error in dest2')
        # mock_dest3.close never called

        dest.instance_variable_set(:@destinations, [mock_dest1, mock_dest2, mock_dest3])

        expect(mock_dest1).to receive(:close).ordered
        expect(mock_dest2).to receive(:close).ordered
        expect { dest.close }.to raise_error('Close error in dest2')
      end
    end
  end

  describe 'nil record handling' do
    it 'passes nil records to all destinations' do
      dest = described_class.new(
        destinations: [
          [Migration::Destinations::JsonlDestination, { file: jsonl_file }],
          [Migration::Destinations::LookupDestination, {
            file: lookup_file,
            key_field: :email,
            value_field: :objid,
          }],
        ]
      )

      # Write mix of valid and nil records
      dest.write({ email: 'a@test.com', objid: 'uuid-1' })
      dest.write(nil)
      dest.write({ email: 'b@test.com', objid: 'uuid-2' })
      dest.close

      # JSONL should have 2 records (nil skipped)
      jsonl_records = read_jsonl(jsonl_file)
      expect(jsonl_records.size).to eq(2)

      # Lookup should have 2 entries (nil skipped)
      lookup_data = read_json(lookup_file)
      expect(lookup_data.keys.size).to eq(2)
    end
  end

  describe 'three or more destinations' do
    it 'supports arbitrary number of destinations' do
      file1 = File.join(temp_dir, 'out1.jsonl')
      file2 = File.join(temp_dir, 'out2.jsonl')
      file3 = File.join(temp_dir, 'out3.jsonl')

      dest = described_class.new(
        destinations: [
          [Migration::Destinations::JsonlDestination, { file: file1 }],
          [Migration::Destinations::JsonlDestination, { file: file2 }],
          [Migration::Destinations::JsonlDestination, { file: file3 }],
        ]
      )

      dest.write({ key: 'test', value: 42 })
      dest.close

      [file1, file2, file3].each do |f|
        records = read_jsonl(f)
        expect(records.size).to eq(1)
        expect(records.first[:key]).to eq('test')
      end
    end
  end
end
