# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Migration::Schemas::V2::CUSTOMER' do
  before(:each) do
    # Re-register the schema since spec_helper resets schemas before each test
    Migration::Schemas.register(:customer_v2, Migration::Schemas::V2::CUSTOMER)
  end

  let(:valid_customer) do
    {
      'objid' => '0194a700-1234-7abc-8def-0123456789ab',
      'extid' => 'ur0abc123def456ghi789jklmn',
      'custid' => '0194a700-1234-7abc-8def-0123456789ab',
      'v1_custid' => 'user@example.com',
      'v1_identifier' => 'customer:user@example.com:object',
      'migration_status' => 'completed',
      'migrated_at' => '1706140800.0',
      'email' => 'user@example.com',
      'created' => '1706140800.0',
      'updated' => '1706140900.0',
      'role' => 'customer',
      'verified' => 'true',
      'planid' => 'pro',
      'stripe_customer_id' => 'cus_123abc',
      'stripe_subscription_id' => 'sub_456def'
    }
  end

  describe 'valid customer' do
    it 'passes validation with all required fields' do
      errors = Migration::Schemas.validate(:customer_v2, valid_customer)

      expect(errors).to be_empty
    end

    it 'passes validation with only required fields' do
      minimal_customer = {
        'objid' => '0194a700-1234-7abc-8def-0123456789ab',
        'custid' => '0194a700-1234-7abc-8def-0123456789ab',
        'migration_status' => 'completed',
        'migrated_at' => '1706140800.0'
      }

      expect(Migration::Schemas.valid?(:customer_v2, minimal_customer)).to be true
    end

    it 'allows additional properties' do
      customer_with_extra = valid_customer.merge('custom_field' => 'value')

      expect(Migration::Schemas.valid?(:customer_v2, customer_with_extra)).to be true
    end
  end

  describe 'objid field (UUIDv7)' do
    it 'fails when objid is missing' do
      customer = valid_customer.dup
      customer.delete('objid')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('objid') }).to be true
    end

    it 'passes with valid UUIDv7 format' do
      # Version 7, variant 8-b
      customer = valid_customer.merge('objid' => '0194a700-0000-7000-8000-000000000000')

      expect(Migration::Schemas.valid?(:customer_v2, customer)).to be true
    end

    it 'fails with wrong version (not 7)' do
      # Version 4 UUID instead of version 7
      customer = valid_customer.merge('objid' => '0194a700-0000-4000-8000-000000000000')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('objid') }).to be true
    end

    it 'fails with wrong variant (not 8-b)' do
      # Variant 0-7 instead of 8-b
      customer = valid_customer.merge('objid' => '0194a700-0000-7000-0000-000000000000')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
    end

    it 'fails with variant c-f (wrong variant)' do
      # Variant c instead of 8-b
      customer = valid_customer.merge('objid' => '0194a700-0000-7000-c000-000000000000')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
    end

    it 'fails with uppercase UUID' do
      customer = valid_customer.merge('objid' => '0194A700-1234-7ABC-8DEF-0123456789AB')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
    end

    it 'fails with UUID missing hyphens' do
      customer = valid_customer.merge('objid' => '0194a70012347abc8def0123456789ab')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
    end

    it 'fails with too short UUID' do
      customer = valid_customer.merge('objid' => '0194a700-1234-7abc-8def')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
    end
  end

  describe 'extid field' do
    it 'passes with valid ur prefix and alphanumeric content' do
      customer = valid_customer.merge('extid' => 'ur0abc123def456ghi789jklmn')

      expect(Migration::Schemas.valid?(:customer_v2, customer)).to be true
    end

    it 'fails without ur prefix' do
      customer = valid_customer.merge('extid' => '0abc123def456ghi789jklmn')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('extid') }).to be true
    end

    it 'fails with wrong prefix' do
      customer = valid_customer.merge('extid' => 'cd0abc123def456ghi789jklmn')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
    end

    it 'fails with special characters after prefix' do
      customer = valid_customer.merge('extid' => 'ur0abc-123_def')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
    end

    it 'passes when extid is absent (optional)' do
      customer = valid_customer.dup
      customer.delete('extid')

      expect(Migration::Schemas.valid?(:customer_v2, customer)).to be true
    end

    it 'passes with mixed case alphanumeric after prefix' do
      customer = valid_customer.merge('extid' => 'urAbC123XyZ')

      expect(Migration::Schemas.valid?(:customer_v2, customer)).to be true
    end
  end

  describe 'migration_status field' do
    %w[pending completed failed].each do |status|
      it "passes with valid status '#{status}'" do
        customer = valid_customer.merge('migration_status' => status)

        expect(Migration::Schemas.valid?(:customer_v2, customer)).to be true
      end
    end

    it 'fails when migration_status is missing' do
      customer = valid_customer.dup
      customer.delete('migration_status')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
    end

    it 'fails with invalid status value' do
      customer = valid_customer.merge('migration_status' => 'in_progress')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('migration_status') }).to be true
    end

    it 'fails with empty status' do
      customer = valid_customer.merge('migration_status' => '')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
    end
  end

  describe 'v1_identifier field' do
    it 'passes with valid key format' do
      customer = valid_customer.merge('v1_identifier' => 'customer:user@example.com:object')

      expect(Migration::Schemas.valid?(:customer_v2, customer)).to be true
    end

    it 'passes with complex custid in key' do
      customer = valid_customer.merge('v1_identifier' => 'customer:user+tag@sub.example.com:object')

      expect(Migration::Schemas.valid?(:customer_v2, customer)).to be true
    end

    it 'fails without customer: prefix' do
      customer = valid_customer.merge('v1_identifier' => 'user@example.com:object')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
    end

    it 'fails without :object suffix' do
      customer = valid_customer.merge('v1_identifier' => 'customer:user@example.com')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
    end

    it 'fails with wrong suffix' do
      customer = valid_customer.merge('v1_identifier' => 'customer:user@example.com:hash')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
    end

    it 'passes when v1_identifier is absent (optional)' do
      customer = valid_customer.dup
      customer.delete('v1_identifier')

      expect(Migration::Schemas.valid?(:customer_v2, customer)).to be true
    end
  end

  describe 'migrated_at field' do
    it 'fails when migrated_at is missing' do
      customer = valid_customer.dup
      customer.delete('migrated_at')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
    end

    it 'passes with integer epoch as string' do
      customer = valid_customer.merge('migrated_at' => '1706140800')

      expect(Migration::Schemas.valid?(:customer_v2, customer)).to be true
    end

    it 'passes with float epoch as string' do
      customer = valid_customer.merge('migrated_at' => '1706140800.123')

      expect(Migration::Schemas.valid?(:customer_v2, customer)).to be true
    end

    it 'fails with non-numeric value' do
      customer = valid_customer.merge('migrated_at' => 'now')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
    end
  end

  describe 'inherited V1 fields' do
    describe 'role' do
      %w[customer colonel recipient anonymous].each do |role|
        it "passes with role '#{role}'" do
          customer = valid_customer.merge('role' => role)

          expect(Migration::Schemas.valid?(:customer_v2, customer)).to be true
        end
      end

      it 'fails with invalid role' do
        customer = valid_customer.merge('role' => 'superuser')

        errors = Migration::Schemas.validate(:customer_v2, customer)

        expect(errors).not_to be_empty
      end
    end

    describe 'stripe_customer_id' do
      it 'passes with cus_ prefix' do
        customer = valid_customer.merge('stripe_customer_id' => 'cus_test123')

        expect(Migration::Schemas.valid?(:customer_v2, customer)).to be true
      end

      it 'fails without cus_ prefix' do
        customer = valid_customer.merge('stripe_customer_id' => 'test123')

        errors = Migration::Schemas.validate(:customer_v2, customer)

        expect(errors).not_to be_empty
      end
    end

    describe 'timestamps' do
      it 'validates created field format' do
        customer = valid_customer.merge('created' => 'invalid')

        errors = Migration::Schemas.validate(:customer_v2, customer)

        expect(errors).not_to be_empty
      end

      it 'validates updated field format' do
        customer = valid_customer.merge('updated' => 'invalid')

        errors = Migration::Schemas.validate(:customer_v2, customer)

        expect(errors).not_to be_empty
      end
    end
  end

  describe 'custid field' do
    it 'fails when custid is missing' do
      customer = valid_customer.dup
      customer.delete('custid')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
    end

    it 'fails when custid is empty' do
      customer = valid_customer.merge('custid' => '')

      errors = Migration::Schemas.validate(:customer_v2, customer)

      expect(errors).not_to be_empty
    end

    it 'passes when custid matches objid (expected in V2)' do
      uuid = '0194a700-1234-7abc-8def-0123456789ab'
      customer = valid_customer.merge('objid' => uuid, 'custid' => uuid)

      expect(Migration::Schemas.valid?(:customer_v2, customer)).to be true
    end
  end
end
