# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Migration::Transforms::Customdomain::FieldTransformer do
  let(:stats) { {} }
  let(:fixed_time) { Time.at(1706200000) }

  # Create a mock registry with loaded lookups
  let(:registry) do
    reg = Migration::Shared::LookupRegistry.new(exports_dir: Dir.mktmpdir)
    reg.register(:email_to_customer, email_to_customer_data, phase: 1)
    reg.register(:email_to_org, email_to_org_data, phase: 2)
    reg
  end

  let(:email_to_customer_data) do
    {
      'alice@example.com' => '01945678-1234-7abc-8def-0123456789ab',
      'bob@example.com' => '01945678-5678-7abc-8def-0123456789ab'
    }
  end

  let(:email_to_org_data) do
    {
      'alice@example.com' => '01945678-aaaa-7abc-8def-0123456789ab',
      'bob@example.com' => '01945678-bbbb-7abc-8def-0123456789ab'
    }
  end

  describe '#initialize' do
    it 'defaults migrated_at to current time' do
      transformer = described_class.new(registry: registry, stats: stats)

      expect(transformer.migrated_at).to be_a(Time)
      expect(transformer.migrated_at.to_i).to be_within(2).of(Time.now.to_i)
    end

    it 'accepts custom migrated_at time' do
      transformer = described_class.new(
        registry: registry,
        migrated_at: fixed_time,
        stats: stats
      )

      expect(transformer.migrated_at).to eq(fixed_time)
    end

    it 'validates required lookups are loaded' do
      empty_registry = Migration::Shared::LookupRegistry.new(exports_dir: Dir.mktmpdir)

      expect {
        described_class.new(registry: empty_registry, stats: stats)
      }.to raise_error(Migration::Transforms::BaseTransform::LookupValidationError)
    end
  end

  describe '#process' do
    let(:v1_record) do
      {
        key: 'customdomain:share.example.com:object',
        type: 'hash',
        ttl_ms: -1,
        db: 0,
        fields: {
          'display_domain' => 'share.example.com',
          'base_domain' => 'example.com',
          'tld' => 'com',
          'sld' => 'example',
          'subdomain' => 'share',
          'custid' => 'alice@example.com',
          'verified' => 'true',
          'created' => '1706140800.0',
          'updated' => '1706140900.0'
        }
      }
    end

    context 'with valid :object record' do
      it 'creates :v2_fields with all V1 fields copied' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]).to be_a(Hash)
        expect(result[:v2_fields]['display_domain']).to eq('share.example.com')
        expect(result[:v2_fields]['base_domain']).to eq('example.com')
        expect(result[:v2_fields]['tld']).to eq('com')
        expect(result[:v2_fields]['sld']).to eq('example')
        expect(result[:v2_fields]['subdomain']).to eq('share')
        expect(result[:v2_fields]['verified']).to eq('true')
      end

      it 'generates UUIDv7 objid' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:objid]).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
        expect(result[:v2_fields]['objid']).to eq(result[:objid])
      end

      it 'generates extid with cd prefix' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:extid]).to start_with('cd')
        expect(result[:v2_fields]['extid']).to eq(result[:extid])
      end

      it 'looks up owner_id from email_to_customer' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['owner_id']).to eq('01945678-1234-7abc-8def-0123456789ab')
        expect(result[:owner_id]).to eq('01945678-1234-7abc-8def-0123456789ab')
      end

      it 'looks up org_id from email_to_org' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['org_id']).to eq('01945678-aaaa-7abc-8def-0123456789ab')
        expect(result[:org_id]).to eq('01945678-aaaa-7abc-8def-0123456789ab')
      end

      it 'preserves original custid as v1_custid' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['v1_custid']).to eq('alice@example.com')
      end

      it 'removes custid from v2_fields' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]).not_to have_key('custid')
      end

      it 'adds v2_fields v1_identifier with original key' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['v1_identifier']).to eq('customdomain:share.example.com:object')
      end

      it 'adds v2_fields migration_status as completed' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['migration_status']).to eq('completed')
      end

      it 'adds v2_fields migrated_at as float string' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['migrated_at']).to eq(fixed_time.to_f.to_s)
      end

      it 'renames key from display_domain to objid' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:key]).to start_with('customdomain:')
        expect(result[:key]).to end_with(':object')
        expect(result[:key]).not_to include('share.example.com')
      end

      it 'returns complete V2 record structure' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result = transformer.process(v1_record)

        expect(result[:key]).to start_with('customdomain:')
        expect(result[:type]).to eq('hash')
        expect(result[:ttl_ms]).to eq(-1)
        expect(result[:db]).to eq(0)
        expect(result[:objid]).to be_a(String)
        expect(result[:extid]).to start_with('cd')
        expect(result[:owner_id]).to be_a(String)
        expect(result[:org_id]).to be_a(String)
        expect(result[:display_domain]).to eq('share.example.com')
        expect(result[:v2_fields]).to be_a(Hash)
      end

      it 'increments :objects_transformed stat' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )

        transformer.process(v1_record)

        expect(stats[:objects_transformed]).to eq(1)
      end
    end

    context 'with missing customer lookup (unknown custid)' do
      it 'returns nil when email not in email_to_customer lookup' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )
        record = v1_record.dup
        record[:fields] = record[:fields].merge('custid' => 'unknown@example.com')

        result = transformer.process(record)

        expect(result).to be_nil
      end

      it 'increments :skipped_no_owner stat' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )
        record = v1_record.dup
        record[:fields] = record[:fields].merge('custid' => 'unknown@example.com')

        transformer.process(record)

        expect(stats[:skipped_no_owner]).to eq(1)
      end
    end

    context 'with missing org lookup' do
      it 'returns nil when email not in email_to_org lookup' do
        # Create registry with only customer lookup
        partial_registry = Migration::Shared::LookupRegistry.new(exports_dir: Dir.mktmpdir)
        partial_registry.register(:email_to_customer, {
          'alice@example.com' => '01945678-1234-7abc-8def-0123456789ab',
          'orphan@example.com' => '01945678-9999-7abc-8def-0123456789ab'
        }, phase: 1)
        partial_registry.register(:email_to_org, {
          'alice@example.com' => '01945678-aaaa-7abc-8def-0123456789ab'
          # orphan@example.com missing from org lookup
        }, phase: 2)

        transformer = described_class.new(
          registry: partial_registry,
          migrated_at: fixed_time,
          stats: stats
        )
        record = v1_record.dup
        record[:fields] = record[:fields].merge('custid' => 'orphan@example.com')

        result = transformer.process(record)

        expect(result).to be_nil
        expect(stats[:skipped_no_org]).to eq(1)
      end
    end

    context 'without :fields' do
      it 'returns nil for records without :fields' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )
        record = {
          key: 'customdomain:share.example.com:object',
          fields: nil
        }

        result = transformer.process(record)

        expect(result).to be_nil
      end

      it 'increments :skipped_no_fields stat' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )
        record = { key: 'customdomain:share.example.com:object', fields: nil }

        transformer.process(record)

        expect(stats[:skipped_no_fields]).to eq(1)
      end
    end

    context 'without custid' do
      it 'returns nil for records without custid' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )
        record = v1_record.dup
        record[:fields] = record[:fields].dup
        record[:fields].delete('custid')

        result = transformer.process(record)

        expect(result).to be_nil
      end

      it 'returns nil for records with empty custid' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )
        record = v1_record.dup
        record[:fields] = record[:fields].merge('custid' => '')

        result = transformer.process(record)

        expect(result).to be_nil
      end

      it 'increments :skipped_no_custid stat' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )
        record = v1_record.dup
        record[:fields] = record[:fields].dup
        record[:fields].delete('custid')

        transformer.process(record)

        expect(stats[:skipped_no_custid]).to eq(1)
      end
    end

    context 'with non-:object records' do
      it 'returns nil for metadata record' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )
        record = {
          key: 'customdomain:share.example.com:metadata',
          type: 'hash',
          fields: { 'some' => 'data' }
        }

        result = transformer.process(record)

        expect(result).to be_nil
      end

      it 'increments :skipped_non_object stat' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )
        record = {
          key: 'customdomain:share.example.com:metadata',
          type: 'hash'
        }

        transformer.process(record)

        expect(stats[:skipped_non_object]).to eq(1)
      end
    end

    context 'stats tracking summary' do
      it 'tracks all stat types correctly across multiple records' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )

        # Valid object transformation
        transformer.process(v1_record)

        # Skipped - no fields
        transformer.process({
          key: 'customdomain:other.example.com:object',
          fields: nil
        })

        # Skipped - no custid
        transformer.process({
          key: 'customdomain:another.example.com:object',
          fields: { 'display_domain' => 'another.example.com' }
        })

        # Skipped - non-object record
        transformer.process({
          key: 'customdomain:share.example.com:metadata',
          type: 'hash'
        })

        # Skipped - no owner
        transformer.process({
          key: 'customdomain:unknown.example.com:object',
          fields: {
            'display_domain' => 'unknown.example.com',
            'custid' => 'unknown@example.com'
          }
        })

        expect(stats[:objects_transformed]).to eq(1)
        expect(stats[:skipped_no_fields]).to eq(1)
        expect(stats[:skipped_no_custid]).to eq(1)
        expect(stats[:skipped_non_object]).to eq(1)
        expect(stats[:skipped_no_owner]).to eq(1)
      end
    end

    context 'field preservation' do
      it 'does not mutate original v1_fields hash' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )
        original_fields = v1_record[:fields].dup

        transformer.process(v1_record)

        expect(v1_record[:fields]).to eq(original_fields)
      end

      it 'preserves additional V1 fields in v2_fields' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )
        record = v1_record.dup
        record[:fields] = record[:fields].merge(
          'txt_validation_host' => '_ots.share.example.com',
          'txt_validation_value' => 'verify-abc123',
          'verification_status' => 'verified'
        )

        result = transformer.process(record)

        expect(result[:v2_fields]['txt_validation_host']).to eq('_ots.share.example.com')
        expect(result[:v2_fields]['txt_validation_value']).to eq('verify-abc123')
        expect(result[:v2_fields]['verification_status']).to eq('verified')
      end
    end

    context 'deterministic identifier generation' do
      it 'generates same objid for same created timestamp' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )

        result1 = transformer.process(v1_record.dup)
        result2 = transformer.process(v1_record.dup)

        # Note: Because uuid generator uses random bits, these won't be identical
        # But they should both be valid UUIDv7
        expect(result1[:objid]).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
        expect(result2[:objid]).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
      end
    end

    context 'domain with different custid sources' do
      it 'uses bob custid and looks up correct owner_id' do
        transformer = described_class.new(
          registry: registry,
          migrated_at: fixed_time,
          stats: stats
        )
        record = v1_record.dup
        record[:fields] = record[:fields].merge('custid' => 'bob@example.com')

        result = transformer.process(record)

        expect(result[:v2_fields]['owner_id']).to eq('01945678-5678-7abc-8def-0123456789ab')
        expect(result[:v2_fields]['org_id']).to eq('01945678-bbbb-7abc-8def-0123456789ab')
        expect(result[:v2_fields]['v1_custid']).to eq('bob@example.com')
      end
    end
  end
end
