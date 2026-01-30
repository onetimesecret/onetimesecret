# migrations/2026-01-28/spec/schemas/v2/receipt_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Migration::Schemas::V2::RECEIPT' do
  before(:each) do
    # Re-register the schema since spec_helper resets schemas before each test
    Migration::Schemas.register(:receipt_v2, Migration::Schemas::V2::RECEIPT)
  end

  let(:valid_receipt) do
    {
      'objid' => '0194a700-1234-7abc-8def-0123456789ab',
      'extid' => 'rc0abc123def456ghi789jklmn',
      'key' => 'abc123xyz',
      'owner_id' => '0194a700-5678-7abc-8def-0123456789ab',
      'org_id' => '0194a700-9abc-7def-8012-0123456789ab',
      'domain_id' => '0194a700-cdef-7012-8345-0123456789ab',
      'state' => 'new',
      'v1_identifier' => 'metadata:abc123xyz:object',
      'migration_status' => 'completed',
      'migrated_at' => '1706140800.0',
      'created' => '1706140800.0',
      'updated' => '1706140900.0'
    }
  end

  describe 'valid receipt' do
    it 'passes validation with all fields' do
      errors = Migration::Schemas.validate(:receipt_v2, valid_receipt)

      expect(errors).to be_empty
    end

    it 'passes validation with only required fields' do
      minimal_receipt = {
        'objid' => '0194a700-1234-7abc-8def-0123456789ab',
        'key' => 'secretkey123',
        'migration_status' => 'completed',
        'migrated_at' => '1706140800.0'
      }

      expect(Migration::Schemas.valid?(:receipt_v2, minimal_receipt)).to be true
    end

    it 'allows additional properties' do
      receipt_with_extra = valid_receipt.merge('custom_field' => 'value')

      expect(Migration::Schemas.valid?(:receipt_v2, receipt_with_extra)).to be true
    end
  end

  describe 'objid field (UUIDv7)' do
    it 'fails when objid is missing' do
      receipt = valid_receipt.dup
      receipt.delete('objid')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('objid') }).to be true
    end

    it 'passes with valid UUIDv7 format' do
      # Version 7, variant 8-b
      receipt = valid_receipt.merge('objid' => '0194a700-0000-7000-8000-000000000000')

      expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
    end

    it 'fails with wrong version (not 7)' do
      # Version 4 UUID instead of version 7
      receipt = valid_receipt.merge('objid' => '0194a700-0000-4000-8000-000000000000')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('objid') }).to be true
    end

    it 'fails with wrong variant (not 8-b)' do
      # Variant 0-7 instead of 8-b
      receipt = valid_receipt.merge('objid' => '0194a700-0000-7000-0000-000000000000')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
    end

    it 'fails with variant c-f (wrong variant)' do
      # Variant c instead of 8-b
      receipt = valid_receipt.merge('objid' => '0194a700-0000-7000-c000-000000000000')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
    end

    it 'fails with uppercase UUID' do
      receipt = valid_receipt.merge('objid' => '0194A700-1234-7ABC-8DEF-0123456789AB')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
    end

    it 'fails with UUID missing hyphens' do
      receipt = valid_receipt.merge('objid' => '0194a70012347abc8def0123456789ab')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
    end

    it 'fails with too short UUID' do
      receipt = valid_receipt.merge('objid' => '0194a700-1234-7abc-8def')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
    end
  end

  describe 'extid field' do
    it 'passes with valid rc prefix and alphanumeric content' do
      receipt = valid_receipt.merge('extid' => 'rc0abc123def456ghi789jklmn')

      expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
    end

    it 'fails without rc prefix' do
      receipt = valid_receipt.merge('extid' => '0abc123def456ghi789jklmn')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('extid') }).to be true
    end

    it 'fails with wrong prefix' do
      receipt = valid_receipt.merge('extid' => 'ur0abc123def456ghi789jklmn')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
    end

    it 'fails with special characters after prefix' do
      receipt = valid_receipt.merge('extid' => 'rc0abc-123_def')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
    end

    it 'passes when extid is absent (optional)' do
      receipt = valid_receipt.dup
      receipt.delete('extid')

      expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
    end

    it 'passes with mixed case alphanumeric after prefix' do
      receipt = valid_receipt.merge('extid' => 'rcAbC123XyZ')

      expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
    end
  end

  describe 'owner_id field (UUIDv7)' do
    it 'passes with valid UUIDv7 format' do
      receipt = valid_receipt.merge('owner_id' => '0194a700-0000-7000-8000-000000000000')

      expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
    end

    it 'fails with invalid UUID format' do
      receipt = valid_receipt.merge('owner_id' => 'not-a-uuid')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('owner_id') }).to be true
    end

    it 'passes when owner_id is absent (anonymous secret)' do
      receipt = valid_receipt.dup
      receipt.delete('owner_id')

      expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
    end

    it 'fails with wrong version (not 7)' do
      receipt = valid_receipt.merge('owner_id' => '0194a700-0000-4000-8000-000000000000')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
    end
  end

  describe 'org_id field (UUIDv7)' do
    it 'passes with valid UUIDv7 format' do
      receipt = valid_receipt.merge('org_id' => '0194a700-0000-7000-8000-000000000000')

      expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
    end

    it 'fails with invalid UUID format' do
      receipt = valid_receipt.merge('org_id' => 'invalid')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('org_id') }).to be true
    end

    it 'passes when org_id is absent (anonymous secret)' do
      receipt = valid_receipt.dup
      receipt.delete('org_id')

      expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
    end
  end

  describe 'domain_id field (UUIDv7)' do
    it 'passes with valid UUIDv7 format' do
      receipt = valid_receipt.merge('domain_id' => '0194a700-0000-7000-8000-000000000000')

      expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
    end

    it 'fails with invalid UUID format' do
      receipt = valid_receipt.merge('domain_id' => 'bad-id')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('domain_id') }).to be true
    end

    it 'passes when domain_id is absent (no custom domain)' do
      receipt = valid_receipt.dup
      receipt.delete('domain_id')

      expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
    end
  end

  describe 'state field' do
    %w[new viewed received burned].each do |valid_state|
      it "passes with valid state '#{valid_state}'" do
        receipt = valid_receipt.merge('state' => valid_state)

        expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
      end
    end

    it 'fails with invalid state value' do
      receipt = valid_receipt.merge('state' => 'deleted')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('state') }).to be true
    end

    it 'passes when state is absent (optional)' do
      receipt = valid_receipt.dup
      receipt.delete('state')

      expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
    end
  end

  describe 'migration_status field' do
    %w[pending completed failed].each do |status|
      it "passes with valid status '#{status}'" do
        receipt = valid_receipt.merge('migration_status' => status)

        expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
      end
    end

    it 'fails when migration_status is missing' do
      receipt = valid_receipt.dup
      receipt.delete('migration_status')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
    end

    it 'fails with invalid status value' do
      receipt = valid_receipt.merge('migration_status' => 'in_progress')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('migration_status') }).to be true
    end

    it 'fails with empty status' do
      receipt = valid_receipt.merge('migration_status' => '')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
    end
  end

  describe 'migrated_at field' do
    it 'fails when migrated_at is missing' do
      receipt = valid_receipt.dup
      receipt.delete('migrated_at')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
    end

    it 'passes with integer epoch as string' do
      receipt = valid_receipt.merge('migrated_at' => '1706140800')

      expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
    end

    it 'passes with float epoch as string' do
      receipt = valid_receipt.merge('migrated_at' => '1706140800.123')

      expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
    end

    it 'fails with non-numeric value' do
      receipt = valid_receipt.merge('migrated_at' => 'now')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
    end
  end

  describe 'v1_identifier field' do
    it 'passes with valid metadata key format' do
      receipt = valid_receipt.merge('v1_identifier' => 'metadata:abc123xyz:object')

      expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
    end

    it 'passes with complex key in v1_identifier' do
      receipt = valid_receipt.merge('v1_identifier' => 'metadata:a1b2c3d4e5f6:object')

      expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
    end

    it 'fails without metadata: prefix' do
      receipt = valid_receipt.merge('v1_identifier' => 'abc123xyz:object')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
    end

    it 'fails without :object suffix' do
      receipt = valid_receipt.merge('v1_identifier' => 'metadata:abc123xyz')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
    end

    it 'fails with wrong prefix' do
      receipt = valid_receipt.merge('v1_identifier' => 'customer:abc123xyz:object')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
    end

    it 'passes when v1_identifier is absent (optional)' do
      receipt = valid_receipt.dup
      receipt.delete('v1_identifier')

      expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
    end
  end

  describe 'timestamps' do
    it 'validates created field format' do
      receipt = valid_receipt.merge('created' => 'invalid')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
    end

    it 'validates updated field format' do
      receipt = valid_receipt.merge('updated' => 'invalid')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
    end

    it 'passes when timestamps are absent (optional)' do
      receipt = valid_receipt.dup
      receipt.delete('created')
      receipt.delete('updated')

      expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
    end
  end

  describe 'key field' do
    it 'fails when key is missing' do
      receipt = valid_receipt.dup
      receipt.delete('key')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('key') }).to be true
    end

    it 'fails when key is empty' do
      receipt = valid_receipt.merge('key' => '')

      errors = Migration::Schemas.validate(:receipt_v2, receipt)

      expect(errors).not_to be_empty
    end

    it 'passes with any non-empty string' do
      receipt = valid_receipt.merge('key' => 'any_secret_key_123')

      expect(Migration::Schemas.valid?(:receipt_v2, receipt)).to be true
    end
  end

  describe 'anonymous receipts' do
    it 'passes validation for anonymous receipt (no owner_id, org_id)' do
      anonymous_receipt = {
        'objid' => '0194a700-1234-7abc-8def-0123456789ab',
        'key' => 'anonkey123',
        'state' => 'new',
        'migration_status' => 'completed',
        'migrated_at' => '1706140800.0',
        'v1_identifier' => 'metadata:anonkey123:object'
      }

      expect(Migration::Schemas.valid?(:receipt_v2, anonymous_receipt)).to be true
    end

    it 'passes validation with owner but no org (edge case)' do
      receipt_with_owner_only = {
        'objid' => '0194a700-1234-7abc-8def-0123456789ab',
        'key' => 'secretkey456',
        'owner_id' => '0194a700-5678-7abc-8def-0123456789ab',
        'migration_status' => 'completed',
        'migrated_at' => '1706140800.0'
      }

      expect(Migration::Schemas.valid?(:receipt_v2, receipt_with_owner_only)).to be true
    end
  end
end
