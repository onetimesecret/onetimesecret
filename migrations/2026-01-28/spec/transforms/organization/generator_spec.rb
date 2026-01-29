# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Migration::Transforms::Organization::Generator do
  let(:stats) { {} }
  let(:migrated_at) { Time.at(1706140800) }
  let(:generator) { described_class.new(stats: stats, migrated_at: migrated_at) }

  # Valid customer record as output from Phase 1
  let(:customer_objid) { '0194a700-1234-7abc-8def-0123456789ab' }
  let(:customer_record) do
    {
      key: 'customer:user@example.com:object',
      type: 'hash',
      ttl_ms: -1,
      db: 0,
      objid: customer_objid,
      extid: 'ur0abc123def456ghi789jklmn',
      created: 1706140800,
      fields: {
        'objid' => customer_objid,
        'extid' => 'ur0abc123def456ghi789jklmn',
        'custid' => customer_objid,
        'v1_custid' => 'user@example.com',
        'email' => 'user@example.com',
        'created' => '1706140800',
        'updated' => '1706140900',
        'role' => 'customer',
        'verified' => 'true',
        'planid' => 'pro',
        'stripe_customer_id' => 'cus_123abc',
        'stripe_subscription_id' => 'sub_456def',
        'stripe_checkout_email' => 'billing@example.com',
        'migration_status' => 'completed',
        'migrated_at' => '1706140800.0',
      },
    }
  end

  describe '#process' do
    context 'with valid customer object record' do
      it 'generates organization record' do
        result = generator.process(customer_record)

        expect(result).not_to be_nil
        expect(result[:key]).to start_with('organization:')
        expect(result[:key]).to end_with(':object')
        expect(result[:type]).to eq('hash')
      end

      it 'generates deterministic org objid from customer objid' do
        result1 = generator.process(customer_record.dup)
        result2 = generator.process(customer_record.dup)

        expect(result1[:objid]).to eq(result2[:objid])
      end

      it 'generates UUIDv7 format org objid' do
        result = generator.process(customer_record)

        expect(result[:objid]).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
      end

      it 'generates extid with on prefix' do
        result = generator.process(customer_record)

        expect(result[:extid]).to start_with('on')
      end

      it 'sets owner_id to customer objid' do
        result = generator.process(customer_record)

        expect(result[:owner_id]).to eq(customer_objid)
      end

      it 'extracts contact_email from customer fields' do
        result = generator.process(customer_record)

        expect(result[:contact_email]).to eq('user@example.com')
      end

      it 'preserves customer db' do
        result = generator.process(customer_record)

        expect(result[:db]).to eq(0)
      end

      it 'sets ttl_ms to -1 (no expiry)' do
        result = generator.process(customer_record)

        expect(result[:ttl_ms]).to eq(-1)
      end

      it 'includes v2_fields with organization data' do
        result = generator.process(customer_record)

        expect(result[:v2_fields]).to be_a(Hash)
        expect(result[:v2_fields]['objid']).to eq(result[:objid])
        expect(result[:v2_fields]['owner_id']).to eq(customer_objid)
        expect(result[:v2_fields]['contact_email']).to eq('user@example.com')
        expect(result[:v2_fields]['billing_email']).to eq('user@example.com')
        expect(result[:v2_fields]['is_default']).to eq('true')
      end

      it 'derives display_name from email domain' do
        result = generator.process(customer_record)

        expect(result[:v2_fields]['display_name']).to eq("Example's Workspace")
      end

      it 'includes migration tracking fields' do
        result = generator.process(customer_record)

        expect(result[:v2_fields]['v1_identifier']).to eq('customer:user@example.com:object')
        expect(result[:v2_fields]['v1_source_custid']).to eq('user@example.com')
        expect(result[:v2_fields]['migration_status']).to eq('completed')
        expect(result[:v2_fields]['migrated_at']).to eq(migrated_at.to_f.to_s)
      end

      it 'copies Stripe fields from customer' do
        result = generator.process(customer_record)

        expect(result[:v2_fields]['stripe_customer_id']).to eq('cus_123abc')
        expect(result[:v2_fields]['stripe_subscription_id']).to eq('sub_456def')
        expect(result[:v2_fields]['stripe_checkout_email']).to eq('billing@example.com')
      end

      it 'copies planid from customer' do
        result = generator.process(customer_record)

        expect(result[:v2_fields]['planid']).to eq('pro')
      end

      it 'uses customer created timestamp' do
        result = generator.process(customer_record)

        expect(result[:v2_fields]['created']).to eq('1706140800')
        expect(result[:created]).to eq(1706140800)
      end

      it 'sets updated to migrated_at' do
        result = generator.process(customer_record)

        expect(result[:v2_fields]['updated']).to eq(migrated_at.to_f.to_s)
      end

      it 'increments organizations_generated stat' do
        generator.process(customer_record)

        expect(stats[:organizations_generated]).to eq(1)
      end
    end

    context 'with Stripe data' do
      it 'increments stripe_customers stat when stripe_customer_id present' do
        generator.process(customer_record)

        expect(stats[:stripe_customers]).to eq(1)
      end

      it 'increments stripe_subscriptions stat when stripe_subscription_id present' do
        generator.process(customer_record)

        expect(stats[:stripe_subscriptions]).to eq(1)
      end

      it 'does not increment Stripe stats when ids are missing' do
        record = customer_record.dup
        record[:fields] = record[:fields].dup
        record[:fields].delete('stripe_customer_id')
        record[:fields].delete('stripe_subscription_id')

        generator.process(record)

        expect(stats[:stripe_customers]).to be_nil
        expect(stats[:stripe_subscriptions]).to be_nil
      end
    end

    context 'with non-customer key' do
      it 'returns nil for non-customer key' do
        record = customer_record.merge(key: 'secret:abc123:object')

        result = generator.process(record)

        expect(result).to be_nil
        expect(stats[:skipped_non_customer_object]).to eq(1)
      end
    end

    context 'with non-object record' do
      it 'returns nil for metadata record' do
        record = customer_record.merge(key: 'customer:user@example.com:metadata')

        result = generator.process(record)

        expect(result).to be_nil
        expect(stats[:skipped_non_customer_object]).to eq(1)
      end
    end

    context 'with missing customer objid' do
      it 'returns nil when objid is nil' do
        record = customer_record.merge(objid: nil)

        result = generator.process(record)

        expect(result).to be_nil
        expect(stats[:skipped_no_objid]).to eq(1)
      end

      it 'returns nil when objid is empty string' do
        record = customer_record.merge(objid: '')

        result = generator.process(record)

        expect(result).to be_nil
        expect(stats[:skipped_no_objid]).to eq(1)
      end
    end

    context 'with missing fields' do
      it 'returns nil when fields are missing' do
        record = customer_record.dup
        record.delete(:fields)
        record.delete(:v2_fields)

        result = generator.process(record)

        expect(result).to be_nil
        expect(stats[:skipped_no_fields]).to eq(1)
      end
    end

    context 'with v2_fields instead of fields' do
      it 'reads from v2_fields when fields not present' do
        record = customer_record.dup
        record[:v2_fields] = record.delete(:fields)

        result = generator.process(record)

        expect(result).not_to be_nil
        expect(result[:contact_email]).to eq('user@example.com')
      end
    end

    context 'email extraction fallbacks' do
      it 'uses v1_custid when email is missing' do
        record = customer_record.dup
        record[:fields] = record[:fields].dup
        record[:fields].delete('email')

        result = generator.process(record)

        expect(result[:contact_email]).to eq('user@example.com')
      end

      it 'uses custid when both email and v1_custid missing' do
        record = customer_record.dup
        record[:fields] = record[:fields].dup.tap do |f|
          f.delete('email')
          f.delete('v1_custid')
          f['custid'] = 'fallback@example.com'
        end

        result = generator.process(record)

        expect(result[:contact_email]).to eq('fallback@example.com')
      end
    end

    context 'display_name derivation' do
      it 'derives from gmail domain' do
        record = customer_record.dup
        record[:fields] = record[:fields].merge('email' => 'user@gmail.com')

        result = generator.process(record)

        expect(result[:v2_fields]['display_name']).to eq("Gmail's Workspace")
      end

      it 'derives from subdomain' do
        record = customer_record.dup
        record[:fields] = record[:fields].merge('email' => 'user@mail.company.com')

        result = generator.process(record)

        expect(result[:v2_fields]['display_name']).to eq("Mail's Workspace")
      end

      it 'returns default when email is empty' do
        record = customer_record.dup
        record[:fields] = record[:fields].dup.tap do |f|
          f.delete('email')
          f.delete('v1_custid')
          f.delete('custid')
        end

        result = generator.process(record)

        expect(result[:v2_fields]['display_name']).to eq('Default Workspace')
      end
    end

    context 'planid defaults' do
      it 'defaults to free when planid missing' do
        record = customer_record.dup
        record[:fields] = record[:fields].dup
        record[:fields].delete('planid')

        result = generator.process(record)

        expect(result[:v2_fields]['planid']).to eq('free')
      end
    end

    context 'timestamp fallbacks' do
      it 'uses current time when created timestamp missing' do
        record = customer_record.dup
        record[:fields] = record[:fields].dup
        record[:fields].delete('created')
        record.delete(:created)

        result = generator.process(record)

        expect(result[:v2_fields]['created']).not_to be_nil
      end
    end
  end

  describe 'deterministic UUID generation' do
    it 'produces same org_objid for same customer_objid and timestamp' do
      gen1 = described_class.new(stats: {}, migrated_at: migrated_at)
      gen2 = described_class.new(stats: {}, migrated_at: migrated_at)

      result1 = gen1.process(customer_record.dup)
      result2 = gen2.process(customer_record.dup)

      expect(result1[:objid]).to eq(result2[:objid])
    end

    it 'produces different org_objid for different customer_objid' do
      record1 = customer_record.dup
      record2 = customer_record.merge(objid: '0194a700-9999-7abc-8def-0123456789ab')

      result1 = generator.process(record1)
      result2 = generator.process(record2)

      expect(result1[:objid]).not_to eq(result2[:objid])
    end

    it 'preserves chronological ordering based on created timestamp' do
      earlier_record = customer_record.merge(created: 1706140000)
      earlier_record[:fields] = earlier_record[:fields].merge('created' => '1706140000')

      later_record = customer_record.merge(objid: '0194a700-9999-7abc-8def-0123456789ab', created: 1706150000)
      later_record[:fields] = later_record[:fields].merge('created' => '1706150000')

      result1 = generator.process(earlier_record)
      result2 = generator.process(later_record)

      # Extract timestamp portion from UUIDv7 (first 12 hex chars without hyphens)
      ts1 = result1[:objid].gsub('-', '')[0, 12].to_i(16)
      ts2 = result2[:objid].gsub('-', '')[0, 12].to_i(16)

      expect(ts1).to be < ts2
    end
  end

  describe 'extid derivation' do
    it 'derives extid deterministically from objid' do
      result1 = generator.process(customer_record.dup)
      result2 = generator.process(customer_record.dup)

      expect(result1[:extid]).to eq(result2[:extid])
    end

    it 'produces extid of expected length' do
      result = generator.process(customer_record)

      # on prefix + 25 char base36
      expect(result[:extid].length).to eq(27)
    end
  end
end
