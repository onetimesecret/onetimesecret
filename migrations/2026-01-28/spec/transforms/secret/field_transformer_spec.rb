# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Migration::Transforms::Secret::FieldTransformer do
  include TempDirHelper
  include JsonlFileHelper

  let(:stats) { {} }
  let(:fixed_time) { Time.at(1706200000) }
  let(:lookup_registry) { Migration::Shared::LookupRegistry.new(exports_dir: @temp_dir) }

  before(:each) do
    @temp_dir = create_temp_dir

    # Create lookup files that Phase 5 requires
    lookups_dir = File.join(@temp_dir, 'lookups')
    FileUtils.mkdir_p(lookups_dir)

    # email_to_customer lookup (Phase 1)
    File.write(
      File.join(lookups_dir, 'email_to_customer_objid.json'),
      JSON.generate({
        'alice@example.com' => '01945678-1234-7abc-8def-0123456789ab',
        'bob@example.com' => '01945678-5678-7abc-8def-0123456789cd',
      })
    )

    # email_to_org lookup (Phase 2)
    File.write(
      File.join(lookups_dir, 'email_to_org_objid.json'),
      JSON.generate({
        'alice@example.com' => '01945678-aaaa-7abc-8def-0123456789ab',
        'bob@example.com' => '01945678-bbbb-7abc-8def-0123456789cd',
      })
    )

    # Load lookups into registry
    lookup_registry.require_lookup(:email_to_customer, for_phase: 5)
    lookup_registry.require_lookup(:email_to_org, for_phase: 5)
  end

  after(:each) do
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
  end

  describe '.required_lookups' do
    it 'requires email_to_customer and email_to_org lookups' do
      expect(described_class.required_lookups).to contain_exactly(:email_to_customer, :email_to_org)
    end
  end

  describe '#initialize' do
    it 'defaults migrated_at to current time' do
      transformer = described_class.new(registry: lookup_registry, stats: stats)

      expect(transformer.migrated_at).to be_a(Time)
      expect(transformer.migrated_at.to_i).to be_within(2).of(Time.now.to_i)
    end

    it 'accepts custom migrated_at time' do
      transformer = described_class.new(
        registry: lookup_registry,
        migrated_at: fixed_time,
        stats: stats
      )

      expect(transformer.migrated_at).to eq(fixed_time)
    end

    it 'accepts lookup registry options' do
      transformer = described_class.new(registry: lookup_registry, stats: stats)

      expect(transformer.registry).to eq(lookup_registry)
    end
  end

  describe '#process' do
    let(:v1_record) do
      {
        key: 'secret:abc123def456:object',
        type: 'hash',
        ttl_ms: 86400000,
        db: 0,
        fields: {
          'key' => 'abc123def456',
          'value' => 'U2FsdGVkX1+encrypted_data_here==',
          'value_checksum' => 'sha256:checksum123',
          'custid' => 'alice@example.com',
          'state' => 'new',
          'passphrase' => '1',
          'secret_ttl' => '86400',
          'created' => '1706140800.0',
          'updated' => '1706140900.0',
        }
      }
    end

    context 'with valid :object record' do
      it 'generates objid based on created timestamp' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:objid]).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
      end

      it 'generates extid with se prefix' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:extid]).to start_with('se')
        expect(result[:extid].length).to be > 2
      end

      it 'CRITICAL: preserves encrypted value exactly' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        # The value MUST be identical - not modified in any way
        expect(result[:v2_fields]['value']).to eq('U2FsdGVkX1+encrypted_data_here==')
      end

      it 'preserves value_checksum' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['value_checksum']).to eq('sha256:checksum123')
      end

      it 'resolves owner_id from custid via email_to_customer lookup' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['owner_id']).to eq('01945678-1234-7abc-8def-0123456789ab')
      end

      it 'resolves org_id from custid via email_to_org lookup' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['org_id']).to eq('01945678-aaaa-7abc-8def-0123456789ab')
      end

      it 'preserves key field' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['key']).to eq('abc123def456')
      end

      it 'preserves state field' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['state']).to eq('new')
      end

      it 'preserves passphrase field' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['passphrase']).to eq('1')
      end

      it 'preserves secret_ttl field' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['secret_ttl']).to eq('86400')
      end

      it 'adds v1_identifier with original key' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['v1_identifier']).to eq('secret:abc123def456:object')
      end

      it 'adds migration_status as completed' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['migration_status']).to eq('completed')
      end

      it 'adds migrated_at as float string' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['migrated_at']).to eq(fixed_time.to_f.to_s)
      end

      it 'renames key from secret_key-based to objid-based' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:key]).to start_with('secret:')
        expect(result[:key]).to end_with(':object')
        expect(result[:key]).to include(result[:objid])
      end

      it 'preserves ttl_ms' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:ttl_ms]).to eq(86400000)
      end

      it 'increments :objects_transformed stat' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        transformer.process(v1_record)

        expect(stats[:objects_transformed]).to eq(1)
      end
    end

    context 'with anonymous secret (no custid)' do
      let(:anonymous_record) do
        {
          key: 'secret:anon123:object',
          type: 'hash',
          ttl_ms: 3600000,
          db: 0,
          fields: {
            'key' => 'anon123',
            'value' => 'encrypted_anon_data',
            'state' => 'new',
            'created' => '1706140800.0',
          }
        }
      end

      it 'processes anonymous secret without owner_id' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(anonymous_record)

        expect(result[:v2_fields]).not_to have_key('owner_id')
        expect(result[:v2_fields]).not_to have_key('org_id')
      end

      it 'CRITICAL: preserves encrypted value for anonymous secrets' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(anonymous_record)

        expect(result[:v2_fields]['value']).to eq('encrypted_anon_data')
      end

      it 'increments :anonymous_secrets stat' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        transformer.process(anonymous_record)

        expect(stats[:anonymous_secrets]).to eq(1)
      end
    end

    context 'with custid=anon' do
      let(:anon_custid_record) do
        {
          key: 'secret:anonkey:object',
          type: 'hash',
          ttl_ms: 3600000,
          db: 0,
          fields: {
            'key' => 'anonkey',
            'value' => 'encrypted_anon_custid_data',
            'custid' => 'anon',
            'state' => 'new',
            'created' => '1706140800.0',
          }
        }
      end

      it 'treats custid=anon as anonymous' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(anon_custid_record)

        expect(result[:v2_fields]).not_to have_key('owner_id')
        expect(stats[:anonymous_secrets]).to eq(1)
      end
    end

    context 'with custid not in lookup' do
      let(:unknown_owner_record) do
        {
          key: 'secret:unknown123:object',
          type: 'hash',
          ttl_ms: 3600000,
          db: 0,
          fields: {
            'key' => 'unknown123',
            'value' => 'encrypted_unknown',
            'custid' => 'unknown@example.com',
            'state' => 'new',
            'created' => '1706140800.0',
          }
        }
      end

      it 'does not set owner_id when not found in lookup' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(unknown_owner_record)

        expect(result[:v2_fields]).not_to have_key('owner_id')
      end

      it 'increments :anonymous_secrets stat for unknown owner' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        transformer.process(unknown_owner_record)

        expect(stats[:anonymous_secrets]).to eq(1)
      end
    end

    context 'with non-:object records' do
      it 'skips non-object records (related passthrough)' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )
        record = { key: 'secret:abc123:metadata', type: 'hash' }

        result = transformer.process(record)

        expect(result).to eq(record)
        expect(result).not_to have_key(:v2_fields)
      end

      it 'increments :related_passthrough stat' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )
        record = { key: 'secret:abc123:metadata', type: 'hash' }

        transformer.process(record)

        expect(stats[:related_passthrough]).to eq(1)
      end
    end

    context 'with non-secret records' do
      it 'skips non-secret records' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )
        record = { key: 'customer:email@example.com:object', type: 'hash' }

        result = transformer.process(record)

        expect(result).to eq(record)
        expect(result).not_to have_key(:v2_fields)
      end

      it 'increments :skipped_non_secret stat' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )
        record = { key: 'customer:email@example.com:object', type: 'hash' }

        transformer.process(record)

        expect(stats[:skipped_non_secret]).to eq(1)
      end
    end

    context 'without :fields' do
      it 'skips records without fields' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )
        record = { key: 'secret:abc123:object', type: 'hash', fields: nil }

        result = transformer.process(record)

        expect(result).to eq(record)
      end

      it 'increments :skipped_no_fields stat' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )
        record = { key: 'secret:abc123:object', type: 'hash', fields: nil }

        transformer.process(record)

        expect(stats[:skipped_no_fields]).to eq(1)
      end
    end

    context 'field preservation' do
      it 'does not mutate original fields hash' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )
        original_fields = v1_record[:fields].dup

        transformer.process(v1_record)

        expect(v1_record[:fields]).to eq(original_fields)
      end

      it 'preserves timestamps' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['created']).to eq('1706140800.0')
        expect(result[:v2_fields]['updated']).to eq('1706140900.0')
      end
    end

    context 'with binary-like encrypted content' do
      it 'preserves binary content without modification' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )
        binary_value = "\x00\x01\x02encrypted\xFE\xFF"
        record = v1_record.dup
        record[:fields] = record[:fields].merge('value' => binary_value)

        result = transformer.process(record)

        expect(result[:v2_fields]['value']).to eq(binary_value)
      end
    end

    context 'stats tracking summary' do
      it 'tracks all stat types correctly across multiple records' do
        transformer = described_class.new(
          registry: lookup_registry,
          migrated_at: fixed_time,
          stats: stats
        )

        # Valid secret with known owner
        transformer.process(v1_record)

        # Anonymous secret
        transformer.process({
          key: 'secret:anon1:object',
          type: 'hash',
          fields: { 'key' => 'anon1', 'value' => 'enc', 'created' => '1706140800' }
        })

        # Unknown owner
        transformer.process({
          key: 'secret:unk1:object',
          type: 'hash',
          fields: { 'key' => 'unk1', 'value' => 'enc', 'custid' => 'unknown@test.com', 'created' => '1706140800' }
        })

        # Non-object (related passthrough)
        transformer.process({ key: 'secret:meta:metadata', type: 'hash' })

        # Non-secret
        transformer.process({ key: 'customer:x:object', type: 'hash' })

        # No fields
        transformer.process({ key: 'secret:nf:object', type: 'hash', fields: nil })

        expect(stats[:objects_transformed]).to eq(3)
        expect(stats[:anonymous_secrets]).to eq(2) # anon1 + unknown owner
        expect(stats[:related_passthrough]).to eq(1)
        expect(stats[:skipped_non_secret]).to eq(1)
        expect(stats[:skipped_no_fields]).to eq(1)
      end
    end
  end
end
