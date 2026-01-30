# migrations/2026-01-28/spec/transforms/customer/field_transformer_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Migration::Transforms::Customer::FieldTransformer do
  let(:stats) { {} }
  let(:fixed_time) { Time.at(1706200000) }

  describe '#initialize' do
    it 'defaults migrated_at to current time' do
      transformer = described_class.new(stats: stats)

      expect(transformer.migrated_at).to be_a(Time)
      expect(transformer.migrated_at.to_i).to be_within(2).of(Time.now.to_i)
    end

    it 'accepts custom migrated_at time' do
      transformer = described_class.new(migrated_at: fixed_time, stats: stats)

      expect(transformer.migrated_at).to eq(fixed_time)
    end
  end

  describe '#process' do
    let(:v1_record) do
      {
        key: 'customer:alice@example.com:object',
        type: 'hash',
        ttl_ms: -1,
        db: 0,
        objid: '01945678-1234-7abc-8def-0123456789ab',
        extid: 'ur0abc123def456789012345678',
        fields: {
          'custid' => 'alice@example.com',
          'email' => 'alice@example.com',
          'created' => '1706140800.0',
          'role' => 'customer',
          'verified' => 'true'
        }
      }
    end

    context 'with valid :object record' do
      it 'creates :v2_fields with all V1 fields copied' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)

        result = transformer.process(v1_record)

        expect(result[:v2_fields]).to be_a(Hash)
        expect(result[:v2_fields]['email']).to eq('alice@example.com')
        expect(result[:v2_fields]['created']).to eq('1706140800.0')
        expect(result[:v2_fields]['role']).to eq('customer')
        expect(result[:v2_fields]['verified']).to eq('true')
      end

      it 'sets v2_fields objid from record :objid' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['objid']).to eq('01945678-1234-7abc-8def-0123456789ab')
      end

      it 'sets v2_fields extid from record :extid' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['extid']).to eq('ur0abc123def456789012345678')
      end

      it 'preserves original email as v2_fields v1_custid' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['v1_custid']).to eq('alice@example.com')
      end

      it 'updates v2_fields custid to objid value' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['custid']).to eq('01945678-1234-7abc-8def-0123456789ab')
      end

      it 'adds v2_fields v1_identifier with original key' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['v1_identifier']).to eq('customer:alice@example.com:object')
      end

      it 'adds v2_fields migration_status as completed' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['migration_status']).to eq('completed')
      end

      it 'adds v2_fields migrated_at as float string' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)

        result = transformer.process(v1_record)

        expect(result[:v2_fields]['migrated_at']).to eq(fixed_time.to_f.to_s)
      end

      it 'renames key from email-based to objid-based' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)

        result = transformer.process(v1_record)

        expect(result[:key]).to eq('customer:01945678-1234-7abc-8def-0123456789ab:object')
      end

      it 'returns complete V2 record structure' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)

        result = transformer.process(v1_record)

        expect(result[:key]).to eq('customer:01945678-1234-7abc-8def-0123456789ab:object')
        expect(result[:type]).to eq('hash')
        expect(result[:ttl_ms]).to eq(-1)
        expect(result[:db]).to eq(0)
        expect(result[:objid]).to eq('01945678-1234-7abc-8def-0123456789ab')
        expect(result[:extid]).to eq('ur0abc123def456789012345678')
        expect(result[:v2_fields]).to be_a(Hash)
      end

      it 'increments :objects_transformed stat' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)

        transformer.process(v1_record)

        expect(stats[:objects_transformed]).to eq(1)
      end
    end

    context 'with record where custid already equals objid' do
      it 'still preserves v1_custid for lookup consistency' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)
        record = v1_record.dup
        record[:fields] = record[:fields].merge('custid' => '01945678-1234-7abc-8def-0123456789ab')

        result = transformer.process(record)

        # Always preserve v1_custid to ensure lookup file has entries for all customers
        expect(result[:v2_fields]['v1_custid']).to eq('01945678-1234-7abc-8def-0123456789ab')
      end
    end

    context 'with record missing custid field' do
      it 'falls back to email for v1_custid lookup key' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)
        record = v1_record.dup
        record[:fields] = record[:fields].reject { |k, _| k == 'custid' }

        result = transformer.process(record)

        # Uses email as fallback to ensure lookup coverage
        expect(result[:v2_fields]['v1_custid']).to eq('alice@example.com')
      end

      it 'handles empty custid by falling back to email' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)
        record = v1_record.dup
        record[:fields] = record[:fields].merge('custid' => '')

        result = transformer.process(record)

        expect(result[:v2_fields]['v1_custid']).to eq('alice@example.com')
      end

      it 'does not set v1_custid when both custid and email are missing' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)
        record = v1_record.dup
        record[:fields] = record[:fields].reject { |k, _| %w[custid email].include?(k) }

        result = transformer.process(record)

        expect(result[:v2_fields]).not_to have_key('v1_custid')
      end
    end

    context 'without :fields' do
      it 'skips records without :fields and returns original' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)
        record = {
          key: 'customer:test@example.com:object',
          objid: 'objid-123',
          fields: nil
        }

        result = transformer.process(record)

        expect(result).to eq(record)
        expect(result).not_to have_key(:v2_fields)
      end

      it 'increments :skipped_no_fields stat' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)
        record = { key: 'customer:test@example.com:object', objid: 'id', fields: nil }

        transformer.process(record)

        expect(stats[:skipped_no_fields]).to eq(1)
      end
    end

    context 'without :objid' do
      it 'skips records without :objid and returns original' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)
        record = {
          key: 'customer:test@example.com:object',
          fields: { 'custid' => 'test@example.com' }
        }

        result = transformer.process(record)

        expect(result).to eq(record)
        expect(result).not_to have_key(:v2_fields)
      end

      it 'skips records with empty :objid' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)
        record = {
          key: 'customer:test@example.com:object',
          objid: '',
          fields: { 'custid' => 'test@example.com' }
        }

        result = transformer.process(record)

        expect(result).to eq(record)
      end

      it 'increments :skipped_no_objid stat' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)
        record = {
          key: 'customer:test@example.com:object',
          fields: { 'custid' => 'test@example.com' }
        }

        transformer.process(record)

        expect(stats[:skipped_no_objid]).to eq(1)
      end
    end

    context 'with empty :extid' do
      it 'does not set extid in v2_fields when empty' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)
        record = v1_record.merge(extid: '')

        result = transformer.process(record)

        expect(result[:v2_fields]).not_to have_key('extid')
      end

      it 'does not set extid in v2_fields when nil' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)
        record = v1_record.merge(extid: nil)

        result = transformer.process(record)

        expect(result[:v2_fields]).not_to have_key('extid')
      end
    end

    context 'with related records (non-:object)' do
      it 'renames related record key when objid mapping exists' do
        # Shared mapping simulates what IdentifierEnricher populates
        email_mapping = { 'alice@example.com' => '01945678-1234-7abc-8def-0123456789ab' }
        transformer = described_class.new(migrated_at: fixed_time, stats: stats, email_mapping: email_mapping)

        # Process a related record (mapping already populated)
        related_record = {
          key: 'customer:alice@example.com:secrets',
          type: 'zset',
          fields: { 'some' => 'data' }
        }

        result = transformer.process(related_record)

        expect(result[:key]).to eq('customer:01945678-1234-7abc-8def-0123456789ab:secrets')
        expect(result[:v1_key]).to eq('customer:alice@example.com:secrets')
        expect(stats[:related_renamed]).to eq(1)
      end

      it 'renames metadata suffix to receipts' do
        email_mapping = { 'alice@example.com' => '01945678-1234-7abc-8def-0123456789ab' }
        transformer = described_class.new(migrated_at: fixed_time, stats: stats, email_mapping: email_mapping)

        related_record = {
          key: 'customer:alice@example.com:metadata',
          type: 'zset'
        }

        result = transformer.process(related_record)

        expect(result[:key]).to eq('customer:01945678-1234-7abc-8def-0123456789ab:receipts')
        expect(result[:v1_key]).to eq('customer:alice@example.com:metadata')
      end

      it 'renames related record when :object processed after related' do
        # Start with empty mapping
        email_mapping = {}
        transformer = described_class.new(migrated_at: fixed_time, stats: stats, email_mapping: email_mapping)

        # Process :object record first (populates mapping)
        transformer.process(v1_record)

        # Now process related record - metadata becomes receipts
        related_record = {
          key: 'customer:alice@example.com:metadata',
          type: 'hash'
        }
        result = transformer.process(related_record)

        expect(result[:key]).to eq('customer:01945678-1234-7abc-8def-0123456789ab:receipts')
      end

      it 'passes through related record unchanged when no objid mapping exists' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)

        # Process related record without any mapping
        record = {
          key: 'customer:unknown@example.com:metadata',
          type: 'hash',
          fields: { 'some' => 'data' }
        }

        result = transformer.process(record)

        expect(result[:key]).to eq('customer:unknown@example.com:metadata')
        expect(result).not_to have_key(:v1_key)
        expect(stats[:related_no_objid]).to eq(1)
      end

      it 'increments :related_renamed stat for successfully renamed records' do
        email_mapping = { 'alice@example.com' => '01945678-1234-7abc-8def-0123456789ab' }
        transformer = described_class.new(migrated_at: fixed_time, stats: stats, email_mapping: email_mapping)

        # Process multiple related records
        transformer.process({ key: 'customer:alice@example.com:secrets', type: 'zset' })
        transformer.process({ key: 'customer:alice@example.com:sessions', type: 'set' })

        expect(stats[:related_renamed]).to eq(2)
      end

      it 'returns record as-is for non-customer keys without colon' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)
        record = { key: 'other_key_type', type: 'string' }

        result = transformer.process(record)

        expect(result).to eq(record)
        expect(stats).not_to have_key(:related_renamed)
        expect(stats).not_to have_key(:related_no_objid)
      end
    end

    context 'stats tracking summary' do
      it 'tracks all stat types correctly across multiple records' do
        # Pre-populate mapping for alice (simulating IdentifierEnricher)
        email_mapping = { 'alice@example.com' => '01945678-1234-7abc-8def-0123456789ab' }
        transformer = described_class.new(migrated_at: fixed_time, stats: stats, email_mapping: email_mapping)

        # Valid object transformation
        transformer.process(v1_record)

        # Skipped - no fields
        transformer.process({
          key: 'customer:bob@example.com:object',
          objid: 'objid-bob',
          fields: nil
        })

        # Skipped - no objid
        transformer.process({
          key: 'customer:charlie@example.com:object',
          fields: { 'custid' => 'charlie@example.com' }
        })

        # Related record - renamed (alice's mapping exists)
        transformer.process({
          key: 'customer:alice@example.com:metadata',
          type: 'hash'
        })

        # Related record - no objid mapping
        transformer.process({
          key: 'customer:dave@example.com:metadata',
          type: 'hash'
        })

        expect(stats[:objects_transformed]).to eq(1)
        expect(stats[:skipped_no_fields]).to eq(1)
        expect(stats[:skipped_no_objid]).to eq(1)
        expect(stats[:related_renamed]).to eq(1)
        expect(stats[:related_no_objid]).to eq(1)
      end
    end

    context 'field preservation' do
      it 'does not mutate original v1_fields hash' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)
        original_fields = v1_record[:fields].dup

        transformer.process(v1_record)

        expect(v1_record[:fields]).to eq(original_fields)
      end

      it 'preserves additional V1 fields in v2_fields' do
        transformer = described_class.new(migrated_at: fixed_time, stats: stats)
        record = v1_record.dup
        record[:fields] = record[:fields].merge(
          'apitoken' => 'secret-token',
          'custom_field' => 'custom_value'
        )

        result = transformer.process(record)

        expect(result[:v2_fields]['apitoken']).to eq('secret-token')
        expect(result[:v2_fields]['custom_field']).to eq('custom_value')
      end
    end
  end
end
