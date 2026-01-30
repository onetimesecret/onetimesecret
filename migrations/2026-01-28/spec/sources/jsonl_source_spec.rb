# migrations/2026-01-28/spec/sources/jsonl_source_spec.rb
#
# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Migration::Sources::JsonlSource do
  include TempDirHelper
  include JsonlFileHelper

  let(:temp_dir) { create_temp_dir }
  let(:input_file) { File.join(temp_dir, 'input.jsonl') }

  after do
    FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
  end

  describe '#initialize' do
    context 'when input file does not exist' do
      it 'raises ArgumentError' do
        expect {
          described_class.new(file: '/nonexistent/path.jsonl')
        }.to raise_error(ArgumentError, /Input file not found/)
      end
    end

    context 'when input file exists' do
      before { write_jsonl(input_file, []) }

      it 'creates instance without error' do
        source = described_class.new(file: input_file)
        expect(source.file).to eq(input_file)
        expect(source.key_pattern).to be_nil
      end

      it 'accepts key_pattern option' do
        pattern = /^customer:/
        source = described_class.new(file: input_file, key_pattern: pattern)
        expect(source.key_pattern).to eq(pattern)
      end
    end
  end

  describe '#each' do
    context 'with valid JSONL content' do
      let(:records) do
        [
          { key: 'customer:a@test.com:object', type: 'hash', db: 6 },
          { key: 'customer:b@test.com:object', type: 'hash', db: 6 },
          { key: 'customer:c@test.com:object', type: 'hash', db: 6 },
        ]
      end

      before { write_jsonl(input_file, records) }

      it 'yields each line as parsed Hash with symbolized keys' do
        source = described_class.new(file: input_file)
        yielded = []
        source.each { |r| yielded << r }

        expect(yielded.size).to eq(3)
        expect(yielded.first).to be_a(Hash)
        expect(yielded.first[:key]).to eq('customer:a@test.com:object')
        expect(yielded.first[:type]).to eq('hash')
        expect(yielded.first[:db]).to eq(6)
      end

      it 'processes multi-line files correctly' do
        source = described_class.new(file: input_file)
        count = 0
        source.each { |_| count += 1 }
        expect(count).to eq(3)
      end
    end

    context 'with key_pattern filtering' do
      let(:records) do
        [
          { key: 'customer:a@test.com:object', type: 'hash' },
          { key: 'secret:abc123:object', type: 'hash' },
          { key: 'customer:b@test.com:secrets', type: 'zset' },
          { key: 'metadata:global', type: 'hash' },
        ]
      end

      before { write_jsonl(input_file, records) }

      it 'only yields records matching regex on :key' do
        source = described_class.new(file: input_file, key_pattern: /^customer:/)
        yielded = []
        source.each { |r| yielded << r }

        expect(yielded.size).to eq(2)
        expect(yielded.map { |r| r[:key] }).to eq([
          'customer:a@test.com:object',
          'customer:b@test.com:secrets',
        ])
      end

      it 'yields nothing when pattern matches nothing' do
        source = described_class.new(file: input_file, key_pattern: /^nonexistent:/)
        yielded = []
        source.each { |r| yielded << r }
        expect(yielded).to be_empty
      end

      it 'skips records without :key field' do
        # Add a record without key
        File.open(input_file, 'a') { |f| f.puts('{"type":"hash","db":6}') }

        source = described_class.new(file: input_file, key_pattern: /^customer:/)
        yielded = []
        source.each { |r| yielded << r }

        # Should only have the 2 customer records, not the keyless one
        expect(yielded.size).to eq(2)
      end
    end

    context 'with empty lines' do
      before do
        File.open(input_file, 'w') do |f|
          f.puts('{"key":"first","type":"hash"}')
          f.puts('')
          f.puts('   ')
          f.puts('{"key":"second","type":"hash"}')
          f.puts("\t")
        end
      end

      it 'skips empty lines and whitespace-only lines' do
        source = described_class.new(file: input_file)
        yielded = []
        source.each { |r| yielded << r }

        expect(yielded.size).to eq(2)
        expect(yielded.map { |r| r[:key] }).to eq(%w[first second])
      end
    end

    context 'with JSON parse errors' do
      before do
        File.open(input_file, 'w') do |f|
          f.puts('{"key":"valid1","type":"hash"}')
          f.puts('not valid json {{{')
          f.puts('{"key":"valid2","type":"hash"}')
          f.puts('{"broken": }')
          f.puts('{"key":"valid3","type":"hash"}')
        end
      end

      it 'handles parse errors gracefully - warns, skips line, continues' do
        source = described_class.new(file: input_file)
        yielded = []

        # Capture warnings
        warnings = []
        allow(source).to receive(:warn) { |msg| warnings << msg }

        source.each { |r| yielded << r }

        # Should have parsed 3 valid records
        expect(yielded.size).to eq(3)
        expect(yielded.map { |r| r[:key] }).to eq(%w[valid1 valid2 valid3])

        # Should have warned about 2 invalid lines
        expect(warnings.size).to eq(2)
        expect(warnings.first).to match(/JSON parse error/)
      end
    end

    context 'memory efficiency' do
      it 'does not load entire file at once (uses File.foreach)' do
        write_jsonl(input_file, [{ key: 'test' }])
        source = described_class.new(file: input_file)

        # Verify File.foreach is used by checking we can enumerate
        # without loading all into memory
        expect(File).to receive(:foreach).with(input_file).and_call_original
        source.each { |_| }
      end
    end

    context 'with extremely long lines' do
      it 'handles lines exceeding typical buffer sizes' do
        # Create a record with a very long value (1MB+)
        long_value = 'x' * (1024 * 1024)
        records = [{ key: 'long', data: long_value }]
        write_jsonl(input_file, records)

        source = described_class.new(file: input_file)
        yielded = []
        source.each { |r| yielded << r }

        expect(yielded.size).to eq(1)
        expect(yielded.first[:data].length).to eq(1024 * 1024)
      end
    end

    context 'with BOM (byte order mark)' do
      it 'handles UTF-8 BOM at file start' do
        # Write file with UTF-8 BOM
        File.open(input_file, 'wb') do |f|
          f.write("\xEF\xBB\xBF") # UTF-8 BOM
          f.puts('{"key":"first","type":"hash"}')
          f.puts('{"key":"second","type":"hash"}')
        end

        source = described_class.new(file: input_file)
        yielded = []

        # Should either skip BOM or handle gracefully
        # The first line may fail JSON parse due to BOM prefix
        warnings = []
        allow(source).to receive(:warn) { |msg| warnings << msg }

        source.each { |r| yielded << r }

        # At minimum, should process subsequent valid lines
        expect(yielded.size).to be >= 1
      end
    end

    context 'with malformed UTF-8' do
      it 'handles invalid UTF-8 sequences gracefully' do
        File.open(input_file, 'wb') do |f|
          f.puts('{"key":"valid1","type":"hash"}')
          # Invalid UTF-8 sequence (truncated multi-byte)
          f.write("{\"key\":\"bad\xFF\xFE\"}\n")
          f.puts('{"key":"valid2","type":"hash"}')
        end

        source = described_class.new(file: input_file)
        yielded = []
        warnings = []
        allow(source).to receive(:warn) { |msg| warnings << msg }

        source.each { |r| yielded << r }

        # Should process valid records, skip or warn on invalid
        expect(yielded.map { |r| r[:key] }).to include('valid1')
        expect(yielded.map { |r| r[:key] }).to include('valid2')
      end
    end

    context 'with empty file' do
      before { FileUtils.touch(input_file) }

      it 'yields nothing' do
        source = described_class.new(file: input_file)
        yielded = []
        source.each { |r| yielded << r }
        expect(yielded).to be_empty
      end
    end
  end
end
