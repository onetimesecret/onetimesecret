# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Migration::Schemas::V2::SECRET' do
  before(:each) do
    # Re-register the schema since spec_helper resets schemas before each test
    Migration::Schemas.register(:secret_v2, Migration::Schemas::V2::SECRET)
  end

  let(:valid_secret) do
    {
      'objid' => '0194a700-1234-7abc-8def-0123456789ab',
      'extid' => 'se0abc123def456ghi789jklmn',
      'owner_id' => '0194a700-5678-7abc-8def-0123456789ab',
      'org_id' => '0194a700-9012-7abc-8def-0123456789ab',
      'value' => 'U2FsdGVkX1+abc123encrypteddata==',
      'value_checksum' => 'sha256:abc123',
      'state' => 'new',
      'secret_ttl' => '86400',
      'passphrase' => '1',
      'v1_identifier' => 'secret:abc123def456:object',
      'migration_status' => 'completed',
      'migrated_at' => '1706140800.0',
      'created' => '1706140800.0',
      'updated' => '1706140900.0',
    }
  end

  describe 'valid secret' do
    it 'passes validation with all required fields' do
      errors = Migration::Schemas.validate(:secret_v2, valid_secret)

      expect(errors).to be_empty
    end

    it 'passes validation with only required fields' do
      minimal_secret = {
        'objid' => '0194a700-1234-7abc-8def-0123456789ab',
        'value' => 'encryptedcontent',
        'migration_status' => 'completed',
        'migrated_at' => '1706140800.0',
      }

      expect(Migration::Schemas.valid?(:secret_v2, minimal_secret)).to be true
    end

    it 'allows additional properties' do
      secret_with_extra = valid_secret.merge('custom_field' => 'value')

      expect(Migration::Schemas.valid?(:secret_v2, secret_with_extra)).to be true
    end
  end

  describe 'objid field (UUIDv7)' do
    it 'fails when objid is missing' do
      secret = valid_secret.dup
      secret.delete('objid')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('objid') }).to be true
    end

    it 'passes with valid UUIDv7 format' do
      # Version 7, variant 8-b
      secret = valid_secret.merge('objid' => '0194a700-0000-7000-8000-000000000000')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end

    it 'fails with wrong version (not 7)' do
      # Version 4 UUID instead of version 7
      secret = valid_secret.merge('objid' => '0194a700-0000-4000-8000-000000000000')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('objid') }).to be true
    end

    it 'fails with wrong variant (not 8-b)' do
      # Variant 0-7 instead of 8-b
      secret = valid_secret.merge('objid' => '0194a700-0000-7000-0000-000000000000')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
    end

    it 'fails with variant c-f (wrong variant)' do
      # Variant c instead of 8-b
      secret = valid_secret.merge('objid' => '0194a700-0000-7000-c000-000000000000')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
    end

    it 'fails with uppercase UUID' do
      secret = valid_secret.merge('objid' => '0194A700-1234-7ABC-8DEF-0123456789AB')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
    end

    it 'fails with UUID missing hyphens' do
      secret = valid_secret.merge('objid' => '0194a70012347abc8def0123456789ab')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
    end

    it 'fails with too short UUID' do
      secret = valid_secret.merge('objid' => '0194a700-1234-7abc-8def')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
    end
  end

  describe 'extid field' do
    it 'passes with valid se prefix and alphanumeric content' do
      secret = valid_secret.merge('extid' => 'se0abc123def456ghi789jklmn')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end

    it 'fails without se prefix' do
      secret = valid_secret.merge('extid' => '0abc123def456ghi789jklmn')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('extid') }).to be true
    end

    it 'fails with wrong prefix (ur instead of se)' do
      secret = valid_secret.merge('extid' => 'ur0abc123def456ghi789jklmn')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
    end

    it 'fails with special characters after prefix' do
      secret = valid_secret.merge('extid' => 'se0abc-123_def')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
    end

    it 'passes when extid is absent (optional)' do
      secret = valid_secret.dup
      secret.delete('extid')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end

    it 'passes with mixed case alphanumeric after prefix' do
      secret = valid_secret.merge('extid' => 'seAbC123XyZ')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end
  end

  describe 'owner_id field (UUIDv7)' do
    it 'passes with valid UUIDv7 format' do
      secret = valid_secret.merge('owner_id' => '0194a700-0000-7000-8000-000000000000')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end

    it 'passes when owner_id is absent (optional for anonymous secrets)' do
      secret = valid_secret.dup
      secret.delete('owner_id')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end

    it 'fails with invalid UUID format' do
      secret = valid_secret.merge('owner_id' => 'not-a-uuid')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('owner_id') }).to be true
    end

    it 'fails with wrong version (not 7)' do
      secret = valid_secret.merge('owner_id' => '0194a700-0000-4000-8000-000000000000')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
    end
  end

  describe 'org_id field (UUIDv7)' do
    it 'passes with valid UUIDv7 format' do
      secret = valid_secret.merge('org_id' => '0194a700-0000-7000-8000-000000000000')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end

    it 'passes when org_id is absent (optional for anonymous secrets)' do
      secret = valid_secret.dup
      secret.delete('org_id')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end

    it 'fails with invalid UUID format' do
      secret = valid_secret.merge('org_id' => 'not-a-uuid')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('org_id') }).to be true
    end
  end

  describe 'value field (CRITICAL - preserved exactly)' do
    it 'fails when value is missing' do
      secret = valid_secret.dup
      secret.delete('value')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('value') }).to be true
    end

    it 'passes with encrypted value string' do
      secret = valid_secret.merge('value' => 'U2FsdGVkX1+abc123encrypteddata==')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end

    it 'passes with empty value string' do
      secret = valid_secret.merge('value' => '')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end

    it 'passes with base64 encoded content' do
      secret = valid_secret.merge('value' => 'SGVsbG8gV29ybGQh')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end

    it 'passes with binary-like content as string' do
      secret = valid_secret.merge('value' => "\x00\x01\x02encrypted")

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end
  end

  describe 'value_checksum field' do
    it 'passes with valid checksum string' do
      secret = valid_secret.merge('value_checksum' => 'sha256:abc123def456')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end

    it 'passes when value_checksum is absent (optional)' do
      secret = valid_secret.dup
      secret.delete('value_checksum')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end
  end

  describe 'state field' do
    %w[new viewed received burned].each do |state|
      it "passes with valid state '#{state}'" do
        secret = valid_secret.merge('state' => state)

        expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
      end
    end

    it 'fails with invalid state value' do
      secret = valid_secret.merge('state' => 'deleted')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('state') }).to be true
    end
  end

  describe 'secret_ttl field' do
    it 'passes with integer as string' do
      secret = valid_secret.merge('secret_ttl' => '86400')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end

    it 'passes with zero' do
      secret = valid_secret.merge('secret_ttl' => '0')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end

    it 'passes when absent (optional)' do
      secret = valid_secret.dup
      secret.delete('secret_ttl')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end
  end

  describe 'passphrase field' do
    %w[0 1 true false].each do |value|
      it "passes with passphrase='#{value}'" do
        secret = valid_secret.merge('passphrase' => value)

        expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
      end
    end

    it 'passes when absent (optional)' do
      secret = valid_secret.dup
      secret.delete('passphrase')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end
  end

  describe 'migration_status field' do
    %w[pending completed failed].each do |status|
      it "passes with valid status '#{status}'" do
        secret = valid_secret.merge('migration_status' => status)

        expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
      end
    end

    it 'fails when migration_status is missing' do
      secret = valid_secret.dup
      secret.delete('migration_status')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
    end

    it 'fails with invalid status value' do
      secret = valid_secret.merge('migration_status' => 'in_progress')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('migration_status') }).to be true
    end

    it 'fails with empty status' do
      secret = valid_secret.merge('migration_status' => '')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
    end
  end

  describe 'migrated_at field' do
    it 'fails when migrated_at is missing' do
      secret = valid_secret.dup
      secret.delete('migrated_at')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
    end

    it 'passes with integer epoch as string' do
      secret = valid_secret.merge('migrated_at' => '1706140800')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end

    it 'passes with float epoch as string' do
      secret = valid_secret.merge('migrated_at' => '1706140800.123')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end

    it 'fails with non-numeric value' do
      secret = valid_secret.merge('migrated_at' => 'now')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
    end
  end

  describe 'v1_identifier field' do
    it 'passes with valid secret key format' do
      secret = valid_secret.merge('v1_identifier' => 'secret:abc123def456:object')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end

    it 'passes with complex key in v1_identifier' do
      secret = valid_secret.merge('v1_identifier' => 'secret:a1b2c3d4e5f6g7h8:object')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end

    it 'fails without secret: prefix' do
      secret = valid_secret.merge('v1_identifier' => 'abc123def456:object')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
    end

    it 'fails without :object suffix' do
      secret = valid_secret.merge('v1_identifier' => 'secret:abc123def456')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
    end

    it 'fails with wrong suffix' do
      secret = valid_secret.merge('v1_identifier' => 'secret:abc123def456:hash')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
    end

    it 'passes when v1_identifier is absent (optional)' do
      secret = valid_secret.dup
      secret.delete('v1_identifier')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end
  end

  describe 'timestamps' do
    it 'validates created field format' do
      secret = valid_secret.merge('created' => 'invalid')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
    end

    it 'validates updated field format' do
      secret = valid_secret.merge('updated' => 'invalid')

      errors = Migration::Schemas.validate(:secret_v2, secret)

      expect(errors).not_to be_empty
    end

    it 'passes when timestamps are absent (optional)' do
      secret = valid_secret.dup
      secret.delete('created')
      secret.delete('updated')

      expect(Migration::Schemas.valid?(:secret_v2, secret)).to be true
    end
  end

  describe 'anonymous secret (no owner)' do
    it 'passes validation without owner_id and org_id' do
      anonymous_secret = {
        'objid' => '0194a700-1234-7abc-8def-0123456789ab',
        'value' => 'encryptedcontent',
        'state' => 'new',
        'migration_status' => 'completed',
        'migrated_at' => '1706140800.0',
      }

      expect(Migration::Schemas.valid?(:secret_v2, anonymous_secret)).to be true
    end
  end
end
