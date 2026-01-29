# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Migration::Schemas::V2::CUSTOMDOMAIN' do
  before(:each) do
    # Re-register the schema since spec_helper resets schemas before each test
    Migration::Schemas.register(:customdomain_v2, Migration::Schemas::V2::CUSTOMDOMAIN)
  end

  let(:valid_customdomain) do
    {
      'objid' => '0194a700-1234-7abc-8def-0123456789ab',
      'extid' => 'cd0abc123def456ghi789jklmn',
      'display_domain' => 'share.example.com',
      'base_domain' => 'example.com',
      'tld' => 'com',
      'sld' => 'example',
      'subdomain' => 'share',
      'owner_id' => '0194a700-5678-7abc-8def-0123456789ab',
      'org_id' => '0194a700-9abc-7abc-8def-0123456789ab',
      'v1_custid' => 'user@example.com',
      'v1_identifier' => 'customdomain:share.example.com:object',
      'migration_status' => 'completed',
      'migrated_at' => '1706140800.0',
      'verified' => 'true',
      'created' => '1706140800.0',
      'updated' => '1706140900.0'
    }
  end

  describe 'valid customdomain' do
    it 'passes validation with all required fields' do
      errors = Migration::Schemas.validate(:customdomain_v2, valid_customdomain)

      expect(errors).to be_empty
    end

    it 'passes validation with only required fields' do
      minimal_domain = {
        'objid' => '0194a700-1234-7abc-8def-0123456789ab',
        'display_domain' => 'share.example.com',
        'owner_id' => '0194a700-5678-7abc-8def-0123456789ab',
        'migration_status' => 'completed',
        'migrated_at' => '1706140800.0'
      }

      expect(Migration::Schemas.valid?(:customdomain_v2, minimal_domain)).to be true
    end

    it 'allows additional properties' do
      domain_with_extra = valid_customdomain.merge('custom_field' => 'value')

      expect(Migration::Schemas.valid?(:customdomain_v2, domain_with_extra)).to be true
    end
  end

  describe 'objid field (UUIDv7)' do
    it 'fails when objid is missing' do
      domain = valid_customdomain.dup
      domain.delete('objid')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('objid') }).to be true
    end

    it 'passes with valid UUIDv7 format' do
      # Version 7, variant 8-b
      domain = valid_customdomain.merge('objid' => '0194a700-0000-7000-8000-000000000000')

      expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
    end

    it 'fails with wrong version (not 7)' do
      # Version 4 UUID instead of version 7
      domain = valid_customdomain.merge('objid' => '0194a700-0000-4000-8000-000000000000')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('objid') }).to be true
    end

    it 'fails with wrong variant (not 8-b)' do
      # Variant 0-7 instead of 8-b
      domain = valid_customdomain.merge('objid' => '0194a700-0000-7000-0000-000000000000')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
    end

    it 'fails with variant c-f (wrong variant)' do
      # Variant c instead of 8-b
      domain = valid_customdomain.merge('objid' => '0194a700-0000-7000-c000-000000000000')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
    end

    it 'fails with uppercase UUID' do
      domain = valid_customdomain.merge('objid' => '0194A700-1234-7ABC-8DEF-0123456789AB')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
    end

    it 'fails with UUID missing hyphens' do
      domain = valid_customdomain.merge('objid' => '0194a70012347abc8def0123456789ab')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
    end

    it 'fails with too short UUID' do
      domain = valid_customdomain.merge('objid' => '0194a700-1234-7abc-8def')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
    end
  end

  describe 'extid field' do
    it 'passes with valid cd prefix and alphanumeric content' do
      domain = valid_customdomain.merge('extid' => 'cd0abc123def456ghi789jklmn')

      expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
    end

    it 'fails without cd prefix' do
      domain = valid_customdomain.merge('extid' => '0abc123def456ghi789jklmn')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('extid') }).to be true
    end

    it 'fails with wrong prefix' do
      domain = valid_customdomain.merge('extid' => 'ur0abc123def456ghi789jklmn')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
    end

    it 'fails with special characters after prefix' do
      domain = valid_customdomain.merge('extid' => 'cd0abc-123_def')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
    end

    it 'passes when extid is absent (optional)' do
      domain = valid_customdomain.dup
      domain.delete('extid')

      expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
    end

    it 'passes with mixed case alphanumeric after prefix' do
      domain = valid_customdomain.merge('extid' => 'cdAbC123XyZ')

      expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
    end
  end

  describe 'owner_id field (UUIDv7)' do
    it 'fails when owner_id is missing' do
      domain = valid_customdomain.dup
      domain.delete('owner_id')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('owner_id') }).to be true
    end

    it 'passes with valid UUIDv7 format' do
      domain = valid_customdomain.merge('owner_id' => '0194a700-0000-7000-8000-000000000000')

      expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
    end

    it 'fails with invalid UUID format' do
      domain = valid_customdomain.merge('owner_id' => 'not-a-uuid')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('owner_id') }).to be true
    end

    it 'fails with wrong version (not 7)' do
      domain = valid_customdomain.merge('owner_id' => '0194a700-0000-4000-8000-000000000000')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
    end
  end

  describe 'org_id field (UUIDv7)' do
    it 'passes when org_id is absent (optional for anonymous)' do
      domain = valid_customdomain.dup
      domain.delete('org_id')

      expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
    end

    it 'passes with valid UUIDv7 format' do
      domain = valid_customdomain.merge('org_id' => '0194a700-0000-7000-8000-000000000000')

      expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
    end

    it 'fails with invalid UUID format' do
      domain = valid_customdomain.merge('org_id' => 'not-a-uuid')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('org_id') }).to be true
    end

    it 'fails with wrong version (not 7)' do
      domain = valid_customdomain.merge('org_id' => '0194a700-0000-4000-8000-000000000000')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
    end
  end

  describe 'migration_status field' do
    %w[pending completed failed].each do |status|
      it "passes with valid status '#{status}'" do
        domain = valid_customdomain.merge('migration_status' => status)

        expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
      end
    end

    it 'fails when migration_status is missing' do
      domain = valid_customdomain.dup
      domain.delete('migration_status')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
    end

    it 'fails with invalid status value' do
      domain = valid_customdomain.merge('migration_status' => 'in_progress')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('migration_status') }).to be true
    end

    it 'fails with empty status' do
      domain = valid_customdomain.merge('migration_status' => '')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
    end
  end

  describe 'migrated_at field' do
    it 'fails when migrated_at is missing' do
      domain = valid_customdomain.dup
      domain.delete('migrated_at')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
    end

    it 'passes with integer epoch as string' do
      domain = valid_customdomain.merge('migrated_at' => '1706140800')

      expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
    end

    it 'passes with float epoch as string' do
      domain = valid_customdomain.merge('migrated_at' => '1706140800.123')

      expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
    end

    it 'fails with non-numeric value' do
      domain = valid_customdomain.merge('migrated_at' => 'now')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
    end
  end

  describe 'v1_identifier field' do
    it 'passes with valid customdomain key format' do
      domain = valid_customdomain.merge('v1_identifier' => 'customdomain:share.example.com:object')

      expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
    end

    it 'passes with complex domain in key' do
      domain = valid_customdomain.merge('v1_identifier' => 'customdomain:api.staging.example.co.uk:object')

      expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
    end

    it 'fails without customdomain: prefix' do
      domain = valid_customdomain.merge('v1_identifier' => 'share.example.com:object')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
    end

    it 'fails without :object suffix' do
      domain = valid_customdomain.merge('v1_identifier' => 'customdomain:share.example.com')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
    end

    it 'fails with wrong suffix' do
      domain = valid_customdomain.merge('v1_identifier' => 'customdomain:share.example.com:hash')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
    end

    it 'passes when v1_identifier is absent (optional)' do
      domain = valid_customdomain.dup
      domain.delete('v1_identifier')

      expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
    end
  end

  describe 'v1_custid field' do
    it 'passes with email format' do
      domain = valid_customdomain.merge('v1_custid' => 'user@example.com')

      expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
    end

    it 'passes when v1_custid is absent (optional)' do
      domain = valid_customdomain.dup
      domain.delete('v1_custid')

      expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
    end
  end

  describe 'inherited V1 domain fields' do
    describe 'display_domain' do
      it 'fails when display_domain is missing' do
        domain = valid_customdomain.dup
        domain.delete('display_domain')

        errors = Migration::Schemas.validate(:customdomain_v2, domain)

        expect(errors).not_to be_empty
      end

      it 'fails with empty display_domain' do
        domain = valid_customdomain.merge('display_domain' => '')

        errors = Migration::Schemas.validate(:customdomain_v2, domain)

        expect(errors).not_to be_empty
      end
    end

    describe 'optional base_domain' do
      it 'passes when base_domain is absent' do
        domain = valid_customdomain.dup
        domain.delete('base_domain')

        expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
      end

      it 'passes with valid base_domain' do
        domain = valid_customdomain.merge('base_domain' => 'example.com')

        expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
      end
    end

    describe 'optional tld' do
      it 'passes when tld is absent' do
        domain = valid_customdomain.dup
        domain.delete('tld')

        expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
      end

      it 'passes with valid tld' do
        domain = valid_customdomain.merge('tld' => 'com')

        expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
      end
    end

    describe 'optional sld' do
      it 'passes when sld is absent' do
        domain = valid_customdomain.dup
        domain.delete('sld')

        expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
      end

      it 'passes with valid sld' do
        domain = valid_customdomain.merge('sld' => 'example')

        expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
      end
    end

    describe 'verified' do
      %w[true false 0 1].each do |value|
        it "passes with value '#{value}'" do
          domain = valid_customdomain.merge('verified' => value)

          expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
        end
      end

      it 'fails with invalid value' do
        domain = valid_customdomain.merge('verified' => 'yes')

        errors = Migration::Schemas.validate(:customdomain_v2, domain)

        expect(errors).not_to be_empty
      end

      it 'passes when verified is absent (optional)' do
        domain = valid_customdomain.dup
        domain.delete('verified')

        expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
      end
    end

    describe 'verification_status' do
      %w[pending verified failed].each do |valid_status|
        it "passes with verification_status='#{valid_status}'" do
          domain = valid_customdomain.merge('verification_status' => valid_status)

          expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
        end
      end

      it 'fails with invalid verification_status value' do
        domain = valid_customdomain.merge('verification_status' => 'unknown')

        errors = Migration::Schemas.validate(:customdomain_v2, domain)

        expect(errors).not_to be_empty
      end

      it 'passes when verification_status is absent' do
        domain = valid_customdomain.dup
        domain.delete('verification_status')

        expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
      end
    end

    describe 'active' do
      %w[true false 0 1].each do |value|
        it "passes with active='#{value}'" do
          domain = valid_customdomain.merge('active' => value)

          expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
        end
      end

      it 'fails with invalid active value' do
        domain = valid_customdomain.merge('active' => 'yes')

        errors = Migration::Schemas.validate(:customdomain_v2, domain)

        expect(errors).not_to be_empty
      end

      it 'passes when active is absent' do
        domain = valid_customdomain.dup
        domain.delete('active')

        expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
      end
    end
  end

  describe 'timestamps' do
    it 'validates created field format' do
      domain = valid_customdomain.merge('created' => 'invalid')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
    end

    it 'validates updated field format' do
      domain = valid_customdomain.merge('updated' => 'invalid')

      errors = Migration::Schemas.validate(:customdomain_v2, domain)

      expect(errors).not_to be_empty
    end

    it 'passes when timestamps are absent (optional)' do
      domain = valid_customdomain.dup
      domain.delete('created')
      domain.delete('updated')

      expect(Migration::Schemas.valid?(:customdomain_v2, domain)).to be true
    end
  end
end
