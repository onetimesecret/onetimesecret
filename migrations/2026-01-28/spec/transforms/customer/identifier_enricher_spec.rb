# migrations/2026-01-28/spec/transforms/customer/identifier_enricher_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Migration::Transforms::Customer::IdentifierEnricher do
  let(:stats) { {} }

  describe '#initialize' do
    it 'creates a UuidV7Generator instance' do
      enricher = described_class.new(stats: stats)

      # Process a valid record to verify the generator works
      record = {
        key: 'customer:test@example.com:object',
        fields: { 'created' => '1706140800.0' }
      }
      result = enricher.process(record)

      expect(result[:objid]).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-/)
    end
  end

  describe '#process' do
    context 'with valid :object record' do
      let(:record) do
        {
          key: 'customer:alice@example.com:object',
          fields: { 'custid' => 'alice@example.com', 'created' => '1706140800.0' }
        }
      end

      it 'generates objid in UUIDv7 format from timestamp' do
        enricher = described_class.new(stats: stats)

        result = enricher.process(record)

        expect(result[:objid]).to be_a(String)
        # UUIDv7 format: 8-4-4-4-12 with version 7 in third segment
        expect(result[:objid]).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
      end

      it 'generates extid with ur prefix' do
        enricher = described_class.new(stats: stats)

        result = enricher.process(record)

        expect(result[:extid]).to be_a(String)
        expect(result[:extid]).to start_with('ur')
        expect(result[:extid].length).to be > 2
      end

      it 'adds both :objid and :extid keys to record' do
        enricher = described_class.new(stats: stats)

        result = enricher.process(record)

        expect(result).to have_key(:objid)
        expect(result).to have_key(:extid)
      end

      it 'populates email_mapping with custid→objid' do
        email_mapping = {}
        enricher = described_class.new(stats: stats, email_mapping: email_mapping)

        result = enricher.process(record)

        expect(email_mapping['alice@example.com']).to eq(result[:objid])
      end

      it 'uses email field when custid is missing' do
        email_mapping = {}
        enricher = described_class.new(stats: stats, email_mapping: email_mapping)
        record_with_email = {
          key: 'customer:bob@example.com:object',
          fields: { 'email' => 'bob@example.com', 'created' => '1706140800.0' }
        }

        result = enricher.process(record_with_email)

        expect(email_mapping['bob@example.com']).to eq(result[:objid])
      end

      it 'increments :enriched stat' do
        enricher = described_class.new(stats: stats)

        enricher.process(record)

        expect(stats[:enriched]).to eq(1)
      end

      it 'preserves all original record fields' do
        enricher = described_class.new(stats: stats)

        result = enricher.process(record)

        expect(result[:key]).to eq('customer:alice@example.com:object')
        expect(result[:fields]).to eq(record[:fields])
      end
    end

    context 'with record-level :created timestamp' do
      it 'uses record-level :created if available' do
        enricher = described_class.new(stats: stats)
        record = {
          key: 'customer:test@example.com:object',
          created: 1706140800.0,
          fields: { 'created' => '1600000000.0' } # Different timestamp in fields
        }

        result = enricher.process(record)

        expect(result[:objid]).to be_a(String)
        expect(stats[:enriched]).to eq(1)
      end

      it 'falls back to fields created when record-level is absent' do
        enricher = described_class.new(stats: stats)
        record = {
          key: 'customer:test@example.com:object',
          fields: { 'created' => '1706140800.0' }
        }

        result = enricher.process(record)

        expect(result[:objid]).to be_a(String)
        expect(stats[:enriched]).to eq(1)
      end
    end

    context 'with non-:object records' do
      it 'skips records where key does not end with :object' do
        enricher = described_class.new(stats: stats)
        record = {
          key: 'customer:alice@example.com:metadata',
          fields: { 'created' => '1706140800.0' }
        }

        result = enricher.process(record)

        expect(result).not_to have_key(:objid)
        expect(result).not_to have_key(:extid)
      end

      it 'increments :skipped_non_object stat for non-object keys' do
        enricher = described_class.new(stats: stats)

        enricher.process({ key: 'customer:test:secrets', fields: { 'created' => '123' } })
        enricher.process({ key: 'customer:test:metadata', fields: { 'created' => '123' } })

        expect(stats[:skipped_non_object]).to eq(2)
      end

      it 'skips records with nil key' do
        enricher = described_class.new(stats: stats)
        record = { key: nil, fields: { 'created' => '1706140800.0' } }

        result = enricher.process(record)

        expect(result).not_to have_key(:objid)
        expect(stats[:skipped_non_object]).to eq(1)
      end
    end

    context 'with records without valid timestamp' do
      it 'skips records without created in fields' do
        enricher = described_class.new(stats: stats)
        record = {
          key: 'customer:test@example.com:object',
          fields: { 'custid' => 'test@example.com' }
        }

        result = enricher.process(record)

        expect(result).not_to have_key(:objid)
        expect(result).not_to have_key(:extid)
      end

      it 'increments :skipped_no_timestamp stat' do
        enricher = described_class.new(stats: stats)
        record = {
          key: 'customer:test@example.com:object',
          fields: {}
        }

        enricher.process(record)

        expect(stats[:skipped_no_timestamp]).to eq(1)
      end

      it 'skips records with zero timestamp' do
        enricher = described_class.new(stats: stats)
        record = {
          key: 'customer:test@example.com:object',
          fields: { 'created' => '0' }
        }

        result = enricher.process(record)

        expect(result).not_to have_key(:objid)
        expect(stats[:skipped_no_timestamp]).to eq(1)
      end

      it 'skips records with negative timestamp' do
        enricher = described_class.new(stats: stats)
        record = {
          key: 'customer:test@example.com:object',
          fields: { 'created' => '-1' }
        }

        result = enricher.process(record)

        expect(result).not_to have_key(:objid)
        expect(stats[:skipped_no_timestamp]).to eq(1)
      end

      it 'skips records with nil fields' do
        enricher = described_class.new(stats: stats)
        record = {
          key: 'customer:test@example.com:object',
          fields: nil
        }

        result = enricher.process(record)

        expect(result).not_to have_key(:objid)
        expect(stats[:skipped_no_timestamp]).to eq(1)
      end
    end

    context 'with already-enriched records' do
      it 'skips records that already have :objid' do
        enricher = described_class.new(stats: stats)
        record = {
          key: 'customer:test@example.com:object',
          objid: 'existing-objid-12345',
          fields: { 'created' => '1706140800.0' }
        }

        result = enricher.process(record)

        expect(result[:objid]).to eq('existing-objid-12345')
      end

      it 'increments :already_enriched stat' do
        enricher = described_class.new(stats: stats)
        record = {
          key: 'customer:test@example.com:object',
          objid: 'existing-objid',
          fields: { 'created' => '1706140800.0' }
        }

        enricher.process(record)

        expect(stats[:already_enriched]).to eq(1)
      end

      it 'does not skip records with empty string :objid' do
        enricher = described_class.new(stats: stats)
        record = {
          key: 'customer:test@example.com:object',
          objid: '',
          fields: { 'created' => '1706140800.0' }
        }

        result = enricher.process(record)

        expect(result[:objid]).not_to be_empty
        expect(stats[:enriched]).to eq(1)
      end
    end

    context 'stats tracking summary' do
      it 'tracks all stat types correctly across multiple records' do
        enricher = described_class.new(stats: stats)

        # Valid enrichable record
        enricher.process({
          key: 'customer:alice@example.com:object',
          fields: { 'created' => '1706140800.0' }
        })

        # Already enriched
        enricher.process({
          key: 'customer:bob@example.com:object',
          objid: 'already-set',
          fields: { 'created' => '1706140800.0' }
        })

        # Non-object record
        enricher.process({
          key: 'customer:charlie@example.com:secrets',
          fields: { 'created' => '1706140800.0' }
        })

        # No timestamp
        enricher.process({
          key: 'customer:dave@example.com:object',
          fields: {}
        })

        expect(stats[:enriched]).to eq(1)
        expect(stats[:already_enriched]).to eq(1)
        expect(stats[:skipped_non_object]).to eq(1)
        expect(stats[:skipped_no_timestamp]).to eq(1)
      end
    end
  end
end
