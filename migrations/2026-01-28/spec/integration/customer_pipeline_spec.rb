# migrations/2026-01-28/spec/integration/customer_pipeline_spec.rb
#
# frozen_string_literal: true

require_relative '../spec_helper'
require 'kiba'

RSpec.describe 'Customer Migration Pipeline Integration' do
  include TempDirHelper
  include JsonlFileHelper

  let(:temp_dir) { create_temp_dir }
  let(:input_file) { File.join(temp_dir, 'customer_dump.jsonl') }
  let(:output_file) { File.join(temp_dir, 'customer_transformed.jsonl') }
  let(:lookup_file) { File.join(temp_dir, 'lookups', 'email_to_customer_objid.json') }

  # Sample V1 customer data
  let(:v1_records) do
    [
      {
        key: 'customer:alice@example.com:object',
        type: 'hash',
        ttl_ms: -1,
        db: 6,
        created: 1706140800, # Timestamp in record (pre-enriched)
        objid: '0194a700-1234-7abc-8def-0123456789ab',
        extid: 'ur0abc123def456ghi789jkl',
        fields: {
          'custid' => 'alice@example.com',
          'created' => '1706140800.0',
          'role' => 'customer',
          'verified' => 'true',
          'planid' => 'basic',
        },
      },
      {
        key: 'customer:bob@example.com:object',
        type: 'hash',
        ttl_ms: -1,
        db: 6,
        created: 1706140900,
        objid: '0194a700-5678-7abc-9def-0123456789cd',
        extid: 'ur0xyz987uvw654rst321qpo',
        fields: {
          'custid' => 'bob@example.com',
          'created' => '1706140900.0',
          'role' => 'customer',
          'verified' => 'false',
          'planid' => 'pro',
          'locale' => 'en-US',
        },
      },
      {
        key: 'customer:carol@example.com:object',
        type: 'hash',
        ttl_ms: 3600000,
        db: 6,
        created: 1706141000,
        objid: '0194a700-9abc-7def-8012-3456789abcde',
        extid: 'ur0mno456pqr789stu012vwx',
        fields: {
          'custid' => 'carol@example.com',
          'created' => '1706141000.0',
          'role' => 'colonel',
          'verified' => 'true',
          'planid' => 'enterprise',
          'apitoken' => 'tok_12345',
        },
      },
    ]
  end

  # Stats hash for tracking
  let(:stats) do
    {
      records_read: 0,
      objects_found: 0,
      objects_transformed: 0,
      records_written: 0,
      lookup_entries: 0,
      validated: 0,
      validation_failures: 0,
      validation_skipped: 0,
      errors: [],
    }
  end

  let(:migrated_at) { Time.now }

  before do
    FileUtils.mkdir_p(File.dirname(output_file))
    FileUtils.mkdir_p(File.dirname(lookup_file))
  end

  after do
    FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
  end

  # Build a simplified Kiba job for testing (without Redis operations)
  # This tests the transforms, destinations, and pipeline flow
  def build_test_pipeline(input_path, output_path, lookup_path, stats_hash, job_time)
    Kiba.parse do
      # Source: read pre-enriched JSONL
      source Migration::Sources::JsonlSource,
             file: input_path,
             key_pattern: /^customer:.*:object$/

      # Transform: count records
      transform do |record|
        stats_hash[:records_read] += 1
        record
      end

      # Transform: simulate RedisDumpDecoder behavior
      # JSON.parse with symbolize_names creates symbol keys for nested hashes,
      # but real Redis HGETALL returns string keys. Convert to match production.
      transform do |record|
        if record[:fields].is_a?(Hash)
          # Convert symbol keys to string keys (simulating Redis decode)
          string_keyed = record[:fields].transform_keys(&:to_s)
          record[:fields] = string_keyed
        end
        record
      end

      # Transform: count objects
      transform do |record|
        if record[:key]&.end_with?(':object')
          stats_hash[:objects_found] += 1
        end
        record
      end

      # Transform: apply field transformations
      transform Migration::Transforms::Customer::FieldTransformer,
                stats: stats_hash,
                migrated_at: job_time

      # Transform: count written records
      transform do |record|
        stats_hash[:records_written] += 1
        record
      end

      # Destination: composite for JSONL and lookup
      destination Migration::Destinations::CompositeDestination,
                  destinations: [
                    [Migration::Destinations::JsonlDestination, {
                      file: output_path,
                      exclude_fields: %i[fields v2_fields decode_error encode_error validation_errors],
                    }],
                    [Migration::Destinations::LookupDestination, {
                      file: lookup_path,
                      key_field: :v1_custid,
                      value_field: :objid,
                      phase: 1,
                      stats: stats_hash,
                    }],
                  ]
    end
  end

  describe 'full pipeline execution' do
    before do
      write_jsonl(input_file, v1_records)
    end

    it 'transforms V1 input to V2 output with correct structure' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      output_records = read_jsonl(output_file)
      expect(output_records.size).to eq(3)

      # Check first record structure
      alice = output_records.find { |r| r[:key]&.include?(v1_records[0][:objid]) }
      expect(alice).not_to be_nil

      # Key should be renamed to objid-based
      expect(alice[:key]).to eq("customer:#{v1_records[0][:objid]}:object")

      # Should have objid and extid
      expect(alice[:objid]).to eq(v1_records[0][:objid])
      expect(alice[:extid]).to eq(v1_records[0][:extid])

      # Internal fields should be excluded
      expect(alice).not_to have_key(:fields)
      expect(alice).not_to have_key(:v2_fields)
    end

    it 'generates valid UUIDv7 objid pattern' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      output_records = read_jsonl(output_file)
      uuid_v7_pattern = /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

      output_records.each do |record|
        expect(record[:objid]).to match(uuid_v7_pattern)
      end
    end

    it 'generates extid with correct ur prefix' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      output_records = read_jsonl(output_file)
      extid_pattern = /^ur[0-9a-z]+$/

      output_records.each do |record|
        expect(record[:extid]).to match(extid_pattern)
      end
    end

    it 'preserves type and ttl_ms' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      output_records = read_jsonl(output_file)

      # All should be hash type
      expect(output_records.map { |r| r[:type] }).to all(eq('hash'))

      # Check TTL preserved for carol (who had 3600000)
      carol = output_records.find { |r| r[:objid] == v1_records[2][:objid] }
      expect(carol[:ttl_ms]).to eq(3600000)
    end
  end

  describe 'lookup file generation' do
    before do
      write_jsonl(input_file, v1_records)
    end

    it 'creates email_to_customer_objid.json lookup file' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      expect(File.exist?(lookup_file)).to be true
    end

    it 'contains email to objid mappings' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      lookup_data = read_json(lookup_file)

      expect(lookup_data['alice@example.com']).to eq(v1_records[0][:objid])
      expect(lookup_data['bob@example.com']).to eq(v1_records[1][:objid])
      expect(lookup_data['carol@example.com']).to eq(v1_records[2][:objid])
    end

    it 'generates valid JSON format' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      # Should not raise
      expect { JSON.parse(File.read(lookup_file)) }.not_to raise_error
    end
  end

  describe 'stats accumulation' do
    before do
      write_jsonl(input_file, v1_records)
    end

    it 'tracks records_read' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      expect(stats[:records_read]).to eq(3)
    end

    it 'tracks objects_found' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      expect(stats[:objects_found]).to eq(3)
    end

    it 'tracks objects_transformed' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      expect(stats[:objects_transformed]).to eq(3)
    end

    it 'tracks records_written' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      expect(stats[:records_written]).to eq(3)
    end

    it 'tracks lookup_entries' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      expect(stats[:lookup_entries]).to eq(3)
    end
  end

  describe 'error handling' do
    context 'with malformed JSONL line' do
      before do
        File.open(input_file, 'w') do |f|
          f.puts(JSON.generate(v1_records[0]))
          f.puts('not valid json {{{')
          f.puts(JSON.generate(v1_records[1]))
        end
      end

      it 'logs and skips malformed lines, continues processing' do
        job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)

        # Should not raise
        expect { Kiba.run(job) }.not_to raise_error

        # Should have processed the 2 valid records
        output_records = read_jsonl(output_file)
        expect(output_records.size).to eq(2)
        expect(stats[:records_read]).to eq(2)
      end
    end

    context 'with missing fields' do
      let(:incomplete_record) do
        {
          key: 'customer:incomplete@example.com:object',
          type: 'hash',
          ttl_ms: -1,
          db: 6,
          # No created, no objid, no fields
        }
      end

      before do
        write_jsonl(input_file, [incomplete_record])
      end

      it 'skips records without objid gracefully' do
        job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
        Kiba.run(job)

        # Record read but not transformed
        expect(stats[:records_read]).to eq(1)
        # Not counted as transformed (no objid)
        expect(stats[:objects_transformed]).to eq(0)
      end
    end

    context 'with record missing fields hash' do
      let(:no_fields_record) do
        {
          key: 'customer:nofields@example.com:object',
          type: 'hash',
          ttl_ms: -1,
          db: 6,
          created: 1706140800,
          objid: '0194a700-aaaa-7bbb-8ccc-ddddeeeeeeee',
          extid: 'urnofields123456789012345',
          # No :fields key
        }
      end

      before do
        write_jsonl(input_file, [no_fields_record])
      end

      it 'skips records without fields hash' do
        job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
        Kiba.run(job)

        expect(stats[:records_read]).to eq(1)
        # FieldTransformer skips records without fields
        expect(stats[:objects_transformed]).to eq(0)
      end
    end
  end

  describe 'key_pattern filtering' do
    let(:mixed_records) do
      [
        v1_records[0],
        {
          key: 'customer:alice@example.com:secrets',
          type: 'zset',
          ttl_ms: -1,
          db: 6,
        },
        {
          key: 'secret:abc123:object',
          type: 'hash',
          ttl_ms: 86400000,
          db: 6,
        },
        v1_records[1],
      ]
    end

    before do
      write_jsonl(input_file, mixed_records)
    end

    it 'only processes customer object records' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      # Should only read customer:*:object records due to key_pattern
      expect(stats[:records_read]).to eq(2)

      output_records = read_jsonl(output_file)
      expect(output_records.size).to eq(2)

      keys = output_records.map { |r| r[:key] }
      expect(keys).to all(match(/^customer:.*:object$/))
    end
  end

  describe 'field transformation details' do
    before do
      write_jsonl(input_file, [v1_records[0]])
    end

    it 'includes migration tracking fields in v2_fields' do
      # Capture variables for Kiba.parse block (closures don't see RSpec let blocks)
      input_path = input_file
      output_path = output_file
      stats_hash = stats
      job_time = migrated_at
      expected_objid = v1_records[0][:objid]

      # Build pipeline that doesn't exclude v2_fields
      job = Kiba.parse do
        source Migration::Sources::JsonlSource,
               file: input_path,
               key_pattern: /^customer:.*:object$/

        # Simulate Redis decode - convert symbol keys to string keys
        transform do |record|
          if record[:fields].is_a?(Hash)
            record[:fields] = record[:fields].transform_keys(&:to_s)
          end
          record
        end

        transform Migration::Transforms::Customer::FieldTransformer,
                  stats: stats_hash,
                  migrated_at: job_time

        destination Migration::Destinations::JsonlDestination,
                    file: output_path
                    # No exclude_fields
      end

      Kiba.run(job)

      output = read_jsonl(output_file).first
      v2_fields = output[:v2_fields]

      # Note: JSON.parse with symbolize_names converts nested hash keys to symbols too
      expect(v2_fields[:migration_status]).to eq('completed')
      expect(v2_fields[:migrated_at]).to eq(migrated_at.to_f.to_s)
      expect(v2_fields[:v1_identifier]).to eq('customer:alice@example.com:object')
      expect(v2_fields[:v1_custid]).to eq('alice@example.com')
      expect(v2_fields[:objid]).to eq(expected_objid)
      expect(v2_fields[:custid]).to eq(expected_objid) # custid now equals objid
    end
  end

  describe 'round-trip verification' do
    before do
      write_jsonl(input_file, v1_records)
    end

    it 'output can be read back as JsonlSource input' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      # Read the output back as a new source
      source = Migration::Sources::JsonlSource.new(file: output_file)
      read_back = []
      source.each { |r| read_back << r }

      expect(read_back.size).to eq(3)
      expect(read_back.first[:key]).to include(':object')
    end
  end

  describe 'empty input handling' do
    before do
      write_jsonl(input_file, [])
    end

    it 'handles empty input file gracefully' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)

      expect { Kiba.run(job) }.not_to raise_error

      expect(stats[:records_read]).to eq(0)
      expect(stats[:records_written]).to eq(0)
    end

    it 'does not create lookup file for empty input' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      # LookupDestination doesn't write file when empty
      expect(File.exist?(lookup_file)).to be false
    end
  end

  describe 'large batch processing' do
    let(:large_batch) do
      100.times.map do |i|
        {
          key: "customer:user#{i}@example.com:object",
          type: 'hash',
          ttl_ms: -1,
          db: 6,
          created: 1706140800 + i,
          objid: "0194a700-#{i.to_s.rjust(4, '0')}-7abc-8def-0123456789ab",
          extid: "ur#{i.to_s.rjust(25, '0')}",
          fields: {
            'custid' => "user#{i}@example.com",
            'created' => (1706140800 + i).to_f.to_s,
            'role' => 'customer',
          },
        }
      end
    end

    before do
      write_jsonl(input_file, large_batch)
    end

    it 'processes large batches efficiently' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Kiba.run(job)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      expect(stats[:records_read]).to eq(100)
      expect(stats[:records_written]).to eq(100)

      # Should complete in reasonable time (less than 5 seconds)
      expect(elapsed).to be < 5.0
    end

    it 'generates all lookup entries' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      lookup_data = read_json(lookup_file)
      expect(lookup_data.keys.size).to eq(100)
    end
  end

  describe 'special character handling' do
    let(:special_char_records) do
      [
        {
          key: 'customer:user+tag@example.com:object',
          type: 'hash',
          ttl_ms: -1,
          db: 6,
          created: 1706140800,
          objid: '0194a700-spec-7abc-8def-000000000001',
          extid: 'urspecialchar00000000001',
          fields: {
            'custid' => 'user+tag@example.com',
            'created' => '1706140800.0',
            'role' => 'customer',
          },
        },
        {
          key: "customer:user's@example.com:object",
          type: 'hash',
          ttl_ms: -1,
          db: 6,
          created: 1706140801,
          objid: '0194a700-spec-7abc-8def-000000000002',
          extid: 'urspecialchar00000000002',
          fields: {
            'custid' => "user's@example.com",
            'created' => '1706140801.0',
            'role' => 'customer',
          },
        },
      ]
    end

    before do
      write_jsonl(input_file, special_char_records)
    end

    it 'handles special characters in email addresses' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      expect(stats[:records_written]).to eq(2)

      lookup_data = read_json(lookup_file)
      expect(lookup_data['user+tag@example.com']).to eq('0194a700-spec-7abc-8def-000000000001')
      expect(lookup_data["user's@example.com"]).to eq('0194a700-spec-7abc-8def-000000000002')
    end
  end

  describe 'duplicate key handling' do
    let(:duplicate_records) do
      [
        {
          key: 'customer:duplicate@example.com:object',
          type: 'hash',
          ttl_ms: -1,
          db: 6,
          created: 1706140800,
          objid: '0194a700-dup1-7abc-8def-000000000001',
          extid: 'urduplicate0000000000001',
          fields: {
            'custid' => 'duplicate@example.com',
            'created' => '1706140800.0',
            'role' => 'customer',
          },
        },
        {
          key: 'customer:duplicate@example.com:object',
          type: 'hash',
          ttl_ms: -1,
          db: 6,
          created: 1706140900,
          objid: '0194a700-dup2-7abc-8def-000000000002',
          extid: 'urduplicate0000000000002',
          fields: {
            'custid' => 'duplicate@example.com',
            'created' => '1706140900.0',
            'role' => 'customer',
          },
        },
      ]
    end

    before do
      write_jsonl(input_file, duplicate_records)
    end

    it 'processes all records even with duplicate custid' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      # Both records should be written to JSONL
      output_records = read_jsonl(output_file)
      expect(output_records.size).to eq(2)
      expect(stats[:records_written]).to eq(2)
    end

    it 'lookup contains last value for duplicate keys' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      lookup_data = read_json(lookup_file)
      # LookupDestination uses last-write-wins semantics
      expect(lookup_data['duplicate@example.com']).to eq('0194a700-dup2-7abc-8def-000000000002')
    end
  end

  describe 'mixed valid and invalid records' do
    let(:mixed_records) do
      [
        # Valid record
        v1_records[0],
        # Record with nil fields - passes through untransformed
        {
          key: 'customer:nilfields@example.com:object',
          type: 'hash',
          ttl_ms: -1,
          db: 6,
          created: 1706140850,
          objid: '0194a700-nil1-7abc-8def-000000000001',
          extid: 'urnilfields0000000000001',
          fields: nil,
        },
        # Another valid record
        v1_records[1],
        # Record missing objid - passes through untransformed
        {
          key: 'customer:noobjid@example.com:object',
          type: 'hash',
          ttl_ms: -1,
          db: 6,
          created: 1706140860,
          # no objid
          fields: {
            'custid' => 'noobjid@example.com',
            'created' => '1706140860.0',
          },
        },
      ]
    end

    before do
      write_jsonl(input_file, mixed_records)
    end

    it 'reads all records but only transforms valid ones' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      # 4 records read, all written (transform passes through invalid records)
      expect(stats[:records_read]).to eq(4)
      # Only 2 fully transformed (alice and bob)
      expect(stats[:objects_transformed]).to eq(2)
      # All 4 written (FieldTransformer returns untransformed records, doesn't filter)
      expect(stats[:records_written]).to eq(4)
    end

    it 'tracks skipped records in stats' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      # FieldTransformer tracks why records were skipped
      expect(stats[:skipped_no_fields]).to eq(1)
      expect(stats[:skipped_no_objid]).to eq(1)
    end

    it 'lookup only contains valid entries with v1_custid' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      lookup_data = read_json(lookup_file)
      # Only transformed records have v1_custid field
      expect(lookup_data.keys.size).to eq(2)
      expect(lookup_data).to have_key('alice@example.com')
      expect(lookup_data).to have_key('bob@example.com')
      # Untransformed records don't have v1_custid, so not in lookup
      expect(lookup_data).not_to have_key('nilfields@example.com')
      expect(lookup_data).not_to have_key('noobjid@example.com')
    end
  end

  describe 'concurrent destination write patterns' do
    before do
      write_jsonl(input_file, v1_records)
    end

    it 'maintains consistency between JSONL and lookup file' do
      job = build_test_pipeline(input_file, output_file, lookup_file, stats, migrated_at)
      Kiba.run(job)

      output_records = read_jsonl(output_file)
      lookup_data = read_json(lookup_file)

      # Every lookup key should have a corresponding JSONL record
      lookup_data.each do |email, objid|
        matching_record = output_records.find { |r| r[:objid] == objid }
        expect(matching_record).not_to be_nil, "Expected JSONL record for objid #{objid}"
      end

      # Every JSONL record with v1_custid should be in lookup
      output_records.each do |record|
        v1_custid = record[:v1_custid]
        if v1_custid
          expect(lookup_data[v1_custid]).to eq(record[:objid])
        end
      end
    end
  end
end
