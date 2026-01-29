# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Migration::Destinations::JsonlDestination do
  include TempDirHelper
  include JsonlFileHelper

  let(:temp_dir) { create_temp_dir }
  let(:output_file) { File.join(temp_dir, 'subdir', 'output.jsonl') }

  after do
    FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
  end

  describe '#initialize' do
    it 'creates output directory if missing' do
      expect(Dir.exist?(File.dirname(output_file))).to be false

      described_class.new(file: output_file)

      expect(Dir.exist?(File.dirname(output_file))).to be true
    end

    it 'sets file path and defaults' do
      dest = described_class.new(file: output_file)

      expect(dest.file).to eq(output_file)
      expect(dest.exclude_fields).to eq([])
      expect(dest.count).to eq(0)
    end

    it 'converts exclude_fields to symbols' do
      dest = described_class.new(file: output_file, exclude_fields: ['foo', :bar, 'baz'])

      expect(dest.exclude_fields).to eq(%i[foo bar baz])
    end
  end

  describe '#write' do
    let(:dest) { described_class.new(file: output_file) }

    after { dest.close }

    context 'with valid records' do
      it 'writes valid JSON per line (parseable back)' do
        record = { key: 'customer:test:object', type: 'hash', db: 6 }
        dest.write(record)
        dest.close

        lines = File.readlines(output_file)
        expect(lines.size).to eq(1)

        parsed = JSON.parse(lines.first, symbolize_names: true)
        expect(parsed).to eq(record)
      end

      it 'accumulates lines with multiple write calls' do
        records = [
          { key: 'first', value: 1 },
          { key: 'second', value: 2 },
          { key: 'third', value: 3 },
        ]

        records.each { |r| dest.write(r) }
        dest.close

        written = read_jsonl(output_file)
        expect(written.size).to eq(3)
        expect(written).to eq(records)
      end

      it 'increments count for each write' do
        3.times { |i| dest.write({ n: i }) }
        expect(dest.count).to eq(3)
      end
    end

    context 'with nil records' do
      it 'handles nil gracefully - does not write' do
        dest.write({ key: 'valid' })
        dest.write(nil)
        dest.write({ key: 'also_valid' })
        dest.close

        written = read_jsonl(output_file)
        expect(written.size).to eq(2)
        expect(dest.count).to eq(2)
      end
    end

    context 'with exclude_fields' do
      let(:dest) do
        described_class.new(
          file: output_file,
          exclude_fields: %i[fields v2_fields internal]
        )
      end

      it 'removes specified symbol keys from output' do
        record = {
          key: 'customer:test:object',
          type: 'hash',
          fields: { 'custid' => 'test@example.com' },
          v2_fields: { 'objid' => 'uuid-123' },
          internal: 'private',
          db: 6,
        }

        dest.write(record)
        dest.close

        written = read_jsonl(output_file).first
        expect(written).to eq({ key: 'customer:test:object', type: 'hash', db: 6 })
        expect(written).not_to have_key(:fields)
        expect(written).not_to have_key(:v2_fields)
        expect(written).not_to have_key(:internal)
      end

      it 'handles string keys in record by converting to symbol for comparison' do
        record = { 'key' => 'test', 'fields' => { 'data' => 1 }, 'type' => 'hash' }

        dest.write(record)
        dest.close

        written = read_jsonl(output_file).first
        # Note: JSON parsing symbolizes keys, so check the output
        expect(written[:key]).to eq('test')
        expect(written[:type]).to eq('hash')
        expect(written).not_to have_key(:fields)
      end
    end
  end

  describe '#close' do
    it 'properly closes file handle' do
      dest = described_class.new(file: output_file)
      dest.write({ key: 'test' })

      # File should be open before close
      expect(dest.instance_variable_get(:@io)).not_to be_nil

      dest.close

      # File handle should be nil after close
      expect(dest.instance_variable_get(:@io)).to be_nil
    end

    it 'can be called multiple times safely' do
      dest = described_class.new(file: output_file)
      dest.write({ key: 'test' })

      expect { dest.close }.not_to raise_error
      expect { dest.close }.not_to raise_error
    end

    it 'handles close when no writes occurred' do
      dest = described_class.new(file: output_file)
      expect { dest.close }.not_to raise_error
    end
  end

  describe 'round-trip with JsonlSource' do
    let(:dest) { described_class.new(file: output_file) }

    it 'written records can be read back by JsonlSource' do
      original_records = [
        { key: 'customer:a@test.com:object', type: 'hash', db: 6, ttl_ms: -1 },
        { key: 'customer:b@test.com:object', type: 'hash', db: 6, ttl_ms: 3600000 },
        { key: 'customer:c@test.com:secrets', type: 'zset', db: 6, ttl_ms: -1 },
      ]

      original_records.each { |r| dest.write(r) }
      dest.close

      # Read back with JsonlSource
      source = Migration::Sources::JsonlSource.new(file: output_file)
      read_back = []
      source.each { |r| read_back << r }

      expect(read_back).to eq(original_records)
    end

    it 'round-trip preserves data types' do
      record = {
        key: 'test',
        string_val: 'hello',
        int_val: 42,
        float_val: 3.14,
        bool_true: true,
        bool_false: false,
        null_val: nil,
        array_val: [1, 2, 3],
        nested: { a: 1, b: 'two' },
      }

      dest.write(record)
      dest.close

      source = Migration::Sources::JsonlSource.new(file: output_file)
      read_back = nil
      source.each { |r| read_back = r }

      expect(read_back[:string_val]).to eq('hello')
      expect(read_back[:int_val]).to eq(42)
      expect(read_back[:float_val]).to eq(3.14)
      expect(read_back[:bool_true]).to eq(true)
      expect(read_back[:bool_false]).to eq(false)
      expect(read_back[:null_val]).to be_nil
      expect(read_back[:array_val]).to eq([1, 2, 3])
      expect(read_back[:nested]).to eq({ a: 1, b: 'two' })
    end
  end
end
