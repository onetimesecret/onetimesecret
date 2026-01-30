# migrations/2026-01-28/spec/schemas/v2/organization_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Migration::Schemas::V2::ORGANIZATION' do
  before(:each) do
    # Re-register the schema since spec_helper resets schemas before each test
    Migration::Schemas.register(:organization_v2, Migration::Schemas::V2::ORGANIZATION)
  end

  let(:valid_organization) do
    {
      'objid' => '0194a700-1234-7abc-8def-0123456789ab',
      'extid' => 'on0abc123def456ghi789jklmn',
      'display_name' => "Example's Workspace",
      'owner_id' => '0194a700-5678-7abc-8def-0123456789ab',
      'contact_email' => 'user@example.com',
      'billing_email' => 'user@example.com',
      'is_default' => 'true',
      'planid' => 'pro',
      'created' => '1706140800.0',
      'updated' => '1706140900.0',
      'stripe_customer_id' => 'cus_123abc',
      'stripe_subscription_id' => 'sub_456def',
      'v1_identifier' => 'customer:user@example.com:object',
      'v1_source_custid' => 'user@example.com',
      'migration_status' => 'completed',
      'migrated_at' => '1706140800.0',
    }
  end

  describe 'valid organization' do
    it 'passes validation with all fields' do
      errors = Migration::Schemas.validate(:organization_v2, valid_organization)

      expect(errors).to be_empty
    end

    it 'passes validation with only required fields' do
      minimal_org = {
        'objid' => '0194a700-1234-7abc-8def-0123456789ab',
        'owner_id' => '0194a700-5678-7abc-8def-0123456789ab',
        'contact_email' => 'user@example.com',
        'is_default' => 'true',
        'migration_status' => 'completed',
        'migrated_at' => '1706140800.0',
      }

      expect(Migration::Schemas.valid?(:organization_v2, minimal_org)).to be true
    end

    it 'allows additional properties' do
      org_with_extra = valid_organization.merge('custom_field' => 'value')

      expect(Migration::Schemas.valid?(:organization_v2, org_with_extra)).to be true
    end
  end

  describe 'objid field (UUIDv7)' do
    it 'fails when objid is missing' do
      org = valid_organization.dup
      org.delete('objid')

      errors = Migration::Schemas.validate(:organization_v2, org)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('objid') }).to be true
    end

    it 'passes with valid UUIDv7 format' do
      org = valid_organization.merge('objid' => '0194a700-0000-7000-8000-000000000000')

      expect(Migration::Schemas.valid?(:organization_v2, org)).to be true
    end

    it 'fails with wrong version (not 7)' do
      org = valid_organization.merge('objid' => '0194a700-0000-4000-8000-000000000000')

      errors = Migration::Schemas.validate(:organization_v2, org)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('objid') }).to be true
    end

    it 'fails with uppercase UUID' do
      org = valid_organization.merge('objid' => '0194A700-1234-7ABC-8DEF-0123456789AB')

      errors = Migration::Schemas.validate(:organization_v2, org)

      expect(errors).not_to be_empty
    end
  end

  describe 'extid field' do
    it 'passes with valid on prefix and alphanumeric content' do
      org = valid_organization.merge('extid' => 'on0abc123def456ghi789jklmn')

      expect(Migration::Schemas.valid?(:organization_v2, org)).to be true
    end

    it 'fails without on prefix' do
      org = valid_organization.merge('extid' => '0abc123def456ghi789jklmn')

      errors = Migration::Schemas.validate(:organization_v2, org)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('extid') }).to be true
    end

    it 'fails with wrong prefix' do
      org = valid_organization.merge('extid' => 'ur0abc123def456ghi789jklmn')

      errors = Migration::Schemas.validate(:organization_v2, org)

      expect(errors).not_to be_empty
    end

    it 'passes when extid is absent (optional)' do
      org = valid_organization.dup
      org.delete('extid')

      expect(Migration::Schemas.valid?(:organization_v2, org)).to be true
    end
  end

  describe 'owner_id field (UUIDv7)' do
    it 'fails when owner_id is missing' do
      org = valid_organization.dup
      org.delete('owner_id')

      errors = Migration::Schemas.validate(:organization_v2, org)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('owner_id') }).to be true
    end

    it 'passes with valid UUIDv7 format' do
      org = valid_organization.merge('owner_id' => '0194a700-0000-7000-8000-000000000000')

      expect(Migration::Schemas.valid?(:organization_v2, org)).to be true
    end

    it 'fails with invalid UUID format' do
      org = valid_organization.merge('owner_id' => 'not-a-uuid')

      errors = Migration::Schemas.validate(:organization_v2, org)

      expect(errors).not_to be_empty
    end
  end

  describe 'contact_email field' do
    it 'fails when contact_email is missing' do
      org = valid_organization.dup
      org.delete('contact_email')

      errors = Migration::Schemas.validate(:organization_v2, org)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('contact_email') }).to be true
    end

    it 'passes with any string value' do
      org = valid_organization.merge('contact_email' => 'test@test.com')

      expect(Migration::Schemas.valid?(:organization_v2, org)).to be true
    end
  end

  describe 'is_default field' do
    %w[true false].each do |value|
      it "passes with value '#{value}'" do
        org = valid_organization.merge('is_default' => value)

        expect(Migration::Schemas.valid?(:organization_v2, org)).to be true
      end
    end

    it 'fails when is_default is missing' do
      org = valid_organization.dup
      org.delete('is_default')

      errors = Migration::Schemas.validate(:organization_v2, org)

      expect(errors).not_to be_empty
    end

    it 'fails with invalid value' do
      org = valid_organization.merge('is_default' => 'yes')

      errors = Migration::Schemas.validate(:organization_v2, org)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('is_default') }).to be true
    end
  end

  describe 'migration_status field' do
    %w[pending completed failed].each do |status|
      it "passes with valid status '#{status}'" do
        org = valid_organization.merge('migration_status' => status)

        expect(Migration::Schemas.valid?(:organization_v2, org)).to be true
      end
    end

    it 'fails when migration_status is missing' do
      org = valid_organization.dup
      org.delete('migration_status')

      errors = Migration::Schemas.validate(:organization_v2, org)

      expect(errors).not_to be_empty
    end

    it 'fails with invalid status value' do
      org = valid_organization.merge('migration_status' => 'in_progress')

      errors = Migration::Schemas.validate(:organization_v2, org)

      expect(errors).not_to be_empty
    end
  end

  describe 'migrated_at field' do
    it 'fails when migrated_at is missing' do
      org = valid_organization.dup
      org.delete('migrated_at')

      errors = Migration::Schemas.validate(:organization_v2, org)

      expect(errors).not_to be_empty
    end

    it 'passes with integer epoch as string' do
      org = valid_organization.merge('migrated_at' => '1706140800')

      expect(Migration::Schemas.valid?(:organization_v2, org)).to be true
    end

    it 'passes with float epoch as string' do
      org = valid_organization.merge('migrated_at' => '1706140800.123')

      expect(Migration::Schemas.valid?(:organization_v2, org)).to be true
    end

    it 'fails with non-numeric value' do
      org = valid_organization.merge('migrated_at' => 'now')

      errors = Migration::Schemas.validate(:organization_v2, org)

      expect(errors).not_to be_empty
    end
  end

  describe 'v1_identifier field' do
    it 'passes with valid customer key format' do
      org = valid_organization.merge('v1_identifier' => 'customer:user@example.com:object')

      expect(Migration::Schemas.valid?(:organization_v2, org)).to be true
    end

    it 'fails without customer: prefix' do
      org = valid_organization.merge('v1_identifier' => 'organization:user@example.com:object')

      errors = Migration::Schemas.validate(:organization_v2, org)

      expect(errors).not_to be_empty
    end

    it 'fails without :object suffix' do
      org = valid_organization.merge('v1_identifier' => 'customer:user@example.com')

      errors = Migration::Schemas.validate(:organization_v2, org)

      expect(errors).not_to be_empty
    end

    it 'passes when v1_identifier is absent (optional)' do
      org = valid_organization.dup
      org.delete('v1_identifier')

      expect(Migration::Schemas.valid?(:organization_v2, org)).to be true
    end
  end

  describe 'stripe fields' do
    describe 'stripe_customer_id' do
      it 'passes with cus_ prefix' do
        org = valid_organization.merge('stripe_customer_id' => 'cus_test123')

        expect(Migration::Schemas.valid?(:organization_v2, org)).to be true
      end

      it 'fails without cus_ prefix' do
        org = valid_organization.merge('stripe_customer_id' => 'test123')

        errors = Migration::Schemas.validate(:organization_v2, org)

        expect(errors).not_to be_empty
      end

      it 'passes when absent (optional)' do
        org = valid_organization.dup
        org.delete('stripe_customer_id')

        expect(Migration::Schemas.valid?(:organization_v2, org)).to be true
      end
    end

    describe 'stripe_subscription_id' do
      it 'passes with sub_ prefix' do
        org = valid_organization.merge('stripe_subscription_id' => 'sub_test123')

        expect(Migration::Schemas.valid?(:organization_v2, org)).to be true
      end

      it 'fails without sub_ prefix' do
        org = valid_organization.merge('stripe_subscription_id' => 'test123')

        errors = Migration::Schemas.validate(:organization_v2, org)

        expect(errors).not_to be_empty
      end

      it 'passes when absent (optional)' do
        org = valid_organization.dup
        org.delete('stripe_subscription_id')

        expect(Migration::Schemas.valid?(:organization_v2, org)).to be true
      end
    end
  end

  describe 'timestamps' do
    it 'validates created field format' do
      org = valid_organization.merge('created' => 'invalid')

      errors = Migration::Schemas.validate(:organization_v2, org)

      expect(errors).not_to be_empty
    end

    it 'validates updated field format' do
      org = valid_organization.merge('updated' => 'invalid')

      errors = Migration::Schemas.validate(:organization_v2, org)

      expect(errors).not_to be_empty
    end

    it 'passes when timestamps are absent (optional)' do
      org = valid_organization.dup
      org.delete('created')
      org.delete('updated')

      expect(Migration::Schemas.valid?(:organization_v2, org)).to be true
    end
  end
end
