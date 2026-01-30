# migrations/2026-01-28/spec/transforms/receipt/field_transformer_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Migration::Transforms::Receipt::FieldTransformer do
  include TempDirHelper
  include JsonlFileHelper

  let(:stats) { {} }
  let(:fixed_time) { Time.at(1706200000) }
  let(:registry) { Migration::Shared::LookupRegistry.new(exports_dir: @temp_dir) }

  before(:each) do
    @temp_dir = create_temp_dir

    # Setup lookup files
    lookups_dir = File.join(@temp_dir, 'lookups')
    FileUtils.mkdir_p(lookups_dir)

    # email_to_customer lookup
    File.write(
      File.join(lookups_dir, 'email_to_customer_objid.json'),
      JSON.generate({
        'alice@example.com' => '0194a700-1111-7abc-8def-0123456789ab',
        'bob@example.com' => '0194a700-2222-7abc-8def-0123456789ab'
      })
    )

    # email_to_org lookup
    File.write(
      File.join(lookups_dir, 'email_to_org_objid.json'),
      JSON.generate({
        'alice@example.com' => '0194a700-3333-7abc-8def-0123456789ab',
        'bob@example.com' => '0194a700-4444-7abc-8def-0123456789ab'
      })
    )

    # fqdn_to_domain lookup
    File.write(
      File.join(lookups_dir, 'fqdn_to_domain_objid.json'),
      JSON.generate({
        'custom.example.com' => '0194a700-5555-7abc-8def-0123456789ab',
        'secrets.acme.com' => '0194a700-6666-7abc-8def-0123456789ab'
      })
    )

    registry.load(:email_to_customer)
    registry.load(:email_to_org)
    registry.load(:fqdn_to_domain)
  end

  after(:each) do
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
  end

  describe '#initialize' do
    it 'defaults migrated_at to current time' do
      transformer = described_class.new(stats: stats, registry: registry)

      expect(transformer.migrated_at).to be_a(Time)
      expect(transformer.migrated_at.to_i).to be_within(2).of(Time.now.to_i)
    end

    it 'accepts custom migrated_at time' do
      transformer = described_class.new(
        migrated_at: fixed_time,
        stats: stats,
        registry: registry
      )

      expect(transformer.migrated_at).to eq(fixed_time)
    end
  end

  describe '#process' do
    let(:v1_record) do
      {
        key: 'metadata:abc123xyz:object',
        type: 'hash',
        ttl_ms: -1,
        db: 0,
        fields: {
          'key' => 'abc123xyz',
          'custid' => 'alice@example.com',
          'state' => 'new',
          'secret_shortkey' => 'xyz789',
          'share_domain' => 'custom.example.com',
          'created' => '1706140800.0',
          'updated' => '1706140900.0'
        }
      }
    end

    context 'with valid :object record' do
      it 'creates :v2_fields with all V1 fields copied' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]).to be_a(Hash)
        expect(result[:v2_fields]['key']).to eq('abc123xyz')
        expect(result[:v2_fields]['created']).to eq('1706140800.0')
        expect(result[:v2_fields]['updated']).to eq('1706140900.0')
      end

      it 'generates deterministic objid from metadata key' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['objid']).to be_a(String)
        expect(result[:v2_fields]['objid']).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
        expect(result[:objid]).to eq(result[:v2_fields]['objid'])
      end

      it 'looks up owner_id from email_to_customer lookup' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['owner_id']).to eq('0194a700-1111-7abc-8def-0123456789ab')
      end

      it 'looks up org_id from email_to_org lookup' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['org_id']).to eq('0194a700-3333-7abc-8def-0123456789ab')
      end

      it 'looks up domain_id from fqdn_to_domain lookup when share_domain present' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['domain_id']).to eq('0194a700-5555-7abc-8def-0123456789ab')
      end

      it 'preserves state field' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['state']).to eq('new')
      end

      it 'adds v1_identifier with original key' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['v1_identifier']).to eq('metadata:abc123xyz:object')
      end

      it 'adds migration_status as completed' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['migration_status']).to eq('completed')
      end

      it 'adds migrated_at as float string' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['migrated_at']).to eq(fixed_time.to_f.to_s)
      end

      it 'renames key from metadata to receipt format' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(v1_record)

        expect(result[:key]).to start_with('receipt:')
        expect(result[:key]).to end_with(':object')
      end

      it 'increments :objects_transformed stat' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        transformer.process(v1_record)

        expect(stats[:objects_transformed]).to eq(1)
      end

      it 'increments :owner_resolved stat when custid found' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        transformer.process(v1_record)

        expect(stats[:owner_resolved]).to eq(1)
      end

      it 'increments :org_resolved stat when org_id found' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        transformer.process(v1_record)

        expect(stats[:org_resolved]).to eq(1)
      end

      it 'increments :domain_resolved stat when domain_id found' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        transformer.process(v1_record)

        expect(stats[:domain_resolved]).to eq(1)
      end
    end

    context 'with non-metadata record' do
      it 'skips non-metadata records and returns nil' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )
        record = {
          key: 'customer:alice@example.com:object',
          type: 'hash',
          fields: { 'custid' => 'alice@example.com' }
        }

        result = transformer.process(record)

        expect(result).to be_nil
      end

      it 'increments :skipped_non_metadata_object stat' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )
        record = {
          key: 'secret:xyz123:object',
          type: 'hash',
          fields: { 'value' => 'secret data' }
        }

        transformer.process(record)

        expect(stats[:skipped_non_metadata_object]).to eq(1)
      end
    end

    context 'with anonymous secrets (no custid)' do
      let(:anonymous_record) do
        {
          key: 'metadata:anon123:object',
          type: 'hash',
          ttl_ms: -1,
          db: 0,
          fields: {
            'key' => 'anon123',
            'state' => 'new',
            'created' => '1706140800.0'
          }
        }
      end

      it 'handles anonymous secrets gracefully' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(anonymous_record)

        expect(result[:v2_fields]).to be_a(Hash)
        expect(result[:v2_fields]['objid']).to be_a(String)
      end

      it 'does not set owner_id for anonymous secrets' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(anonymous_record)

        expect(result[:v2_fields]).not_to have_key('owner_id')
      end

      it 'does not set org_id for anonymous secrets' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(anonymous_record)

        expect(result[:v2_fields]).not_to have_key('org_id')
      end

      it 'increments :no_custid stat' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        transformer.process(anonymous_record)

        expect(stats[:no_custid]).to eq(1)
      end
    end

    context 'without share_domain' do
      it 'does not set domain_id when share_domain is absent' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )
        record = v1_record.dup
        record[:fields] = record[:fields].dup
        record[:fields].delete('share_domain')

        result = transformer.process(record)

        expect(result[:v2_fields]).not_to have_key('domain_id')
      end
    end

    context 'with unknown custid (not in lookup)' do
      it 'does not set owner_id when custid not found in lookup' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )
        record = v1_record.dup
        record[:fields] = record[:fields].merge('custid' => 'unknown@example.com')

        result = transformer.process(record)

        expect(result[:v2_fields]).not_to have_key('owner_id')
      end

      it 'does not set org_id when custid not found in org lookup' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )
        record = v1_record.dup
        record[:fields] = record[:fields].merge('custid' => 'unknown@example.com')

        result = transformer.process(record)

        expect(result[:v2_fields]).not_to have_key('org_id')
      end

      it 'increments :owner_unresolved stat' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )
        record = v1_record.dup
        record[:fields] = record[:fields].merge('custid' => 'unknown@example.com')

        transformer.process(record)

        expect(stats[:owner_unresolved]).to eq(1)
      end

      it 'increments :org_unresolved stat' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )
        record = v1_record.dup
        record[:fields] = record[:fields].merge('custid' => 'unknown@example.com')

        transformer.process(record)

        expect(stats[:org_unresolved]).to eq(1)
      end
    end

    context 'with unknown share_domain (not in lookup)' do
      it 'does not set domain_id when domain not found in lookup' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )
        record = v1_record.dup
        record[:fields] = record[:fields].merge('share_domain' => 'unknown.example.com')

        result = transformer.process(record)

        expect(result[:v2_fields]).not_to have_key('domain_id')
      end

      it 'increments :domain_unresolved stat' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )
        record = v1_record.dup
        record[:fields] = record[:fields].merge('share_domain' => 'unknown.example.com')

        transformer.process(record)

        expect(stats[:domain_unresolved]).to eq(1)
      end
    end

    context 'without :fields' do
      it 'skips records without :fields and returns nil' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )
        record = {
          key: 'metadata:test123:object',
          fields: nil
        }

        result = transformer.process(record)

        expect(result).to be_nil
      end

      it 'increments :skipped_no_fields stat' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )
        record = { key: 'metadata:test123:object', fields: nil }

        transformer.process(record)

        expect(stats[:skipped_no_fields]).to eq(1)
      end
    end

    context 'without secret key in fields' do
      it 'skips records without key field and returns nil' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )
        record = {
          key: 'metadata:test123:object',
          fields: { 'state' => 'new' }
        }

        result = transformer.process(record)

        expect(result).to be_nil
      end

      it 'increments :skipped_no_secret_key stat' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )
        record = {
          key: 'metadata:test123:object',
          fields: { 'state' => 'new' }
        }

        transformer.process(record)

        expect(stats[:skipped_no_secret_key]).to eq(1)
      end
    end

    context 'with related records (non-:object)' do
      it 'skips related metadata records and returns nil' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )
        record = {
          key: 'metadata:abc123xyz:secrets',
          type: 'zset',
          fields: { 'some' => 'data' }
        }

        result = transformer.process(record)

        expect(result).to be_nil
      end

      it 'increments :skipped_non_metadata_object stat for non-object records' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )
        record = {
          key: 'metadata:abc123xyz:state',
          type: 'string'
        }

        transformer.process(record)

        expect(stats[:skipped_non_metadata_object]).to eq(1)
      end
    end

    context 'stats tracking summary' do
      it 'tracks all stat types correctly across multiple records' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        # Valid object transformation with all lookups resolving
        transformer.process(v1_record)

        # Anonymous secret (no custid)
        transformer.process({
          key: 'metadata:anon456:object',
          type: 'hash',
          fields: { 'key' => 'anon456', 'state' => 'new', 'created' => '1706140800.0' }
        })

        # Skipped - no fields
        transformer.process({
          key: 'metadata:nofld789:object',
          fields: nil
        })

        # Skipped - non-object key
        transformer.process({
          key: 'metadata:abc123xyz:state',
          type: 'string'
        })

        # Skipped - non-metadata record
        transformer.process({
          key: 'customer:test@example.com:object',
          type: 'hash',
          fields: { 'custid' => 'test@example.com' }
        })

        expect(stats[:objects_transformed]).to eq(2)
        expect(stats[:no_custid]).to eq(1)
        expect(stats[:skipped_no_fields]).to eq(1)
        expect(stats[:skipped_non_metadata_object]).to eq(2)
      end
    end

    context 'field preservation' do
      it 'does not mutate original fields hash' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )
        original_fields = v1_record[:fields].dup

        transformer.process(v1_record)

        expect(v1_record[:fields]).to eq(original_fields)
      end

      it 'preserves additional V1 fields in v2_fields' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )
        record = v1_record.dup
        record[:fields] = record[:fields].merge(
          'recipients' => 'recipient@example.com',
          'custom_field' => 'custom_value'
        )

        result = transformer.process(record)

        expect(result[:v2_fields]['recipients']).to eq('recipient@example.com')
        expect(result[:v2_fields]['custom_field']).to eq('custom_value')
      end

      it 'preserves v1_custid when custid is present' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['v1_custid']).to eq('alice@example.com')
      end
    end

    context 'deterministic objid generation' do
      it 'generates same objid for same secret key' do
        transformer1 = described_class.new(
          migrated_at: fixed_time,
          stats: {},
          registry: registry
        )
        transformer2 = described_class.new(
          migrated_at: fixed_time,
          stats: {},
          registry: registry
        )

        result1 = transformer1.process(v1_record.dup)
        result2 = transformer2.process(v1_record.dup)

        expect(result1[:v2_fields]['objid']).to eq(result2[:v2_fields]['objid'])
      end

      it 'generates different objid for different secret keys' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        record1 = v1_record.dup
        record1[:key] = 'metadata:key111:object'
        record1[:fields] = record1[:fields].merge('key' => 'key111')

        record2 = v1_record.dup
        record2[:key] = 'metadata:key222:object'
        record2[:fields] = record2[:fields].merge('key' => 'key222')

        result1 = transformer.process(record1)
        result2 = transformer.process(record2)

        expect(result1[:v2_fields]['objid']).not_to eq(result2[:v2_fields]['objid'])
      end

      it 'uses timestamp from created field for objid' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(v1_record)

        # The objid should encode the timestamp 1706140800 (from created field)
        # UUIDv7 first 12 hex chars encode timestamp in ms
        objid = result[:v2_fields]['objid']
        time_hex = objid.delete('-')[0, 12]
        timestamp_ms = time_hex.to_i(16)
        timestamp_s = timestamp_ms / 1000

        expect(timestamp_s).to eq(1706140800)
      end
    end

    context 'extid generation' do
      it 'generates extid with rc prefix' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['extid']).to start_with('rc')
        expect(result[:extid]).to eq(result[:v2_fields]['extid'])
      end
    end

    context 'output record structure' do
      it 'includes secret_key in output record' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(v1_record)

        expect(result[:secret_key]).to eq('abc123xyz')
      end

      it 'preserves ttl_ms from input' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(v1_record)

        expect(result[:ttl_ms]).to eq(-1)
      end

      it 'preserves db from input' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(v1_record)

        expect(result[:db]).to eq(0)
      end

      it 'sets type to hash' do
        transformer = described_class.new(
          migrated_at: fixed_time,
          stats: stats,
          registry: registry
        )

        result = transformer.process(v1_record)

        expect(result[:type]).to eq('hash')
      end
    end
  end
end
