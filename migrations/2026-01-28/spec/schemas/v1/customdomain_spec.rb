# migrations/2026-01-28/spec/schemas/v1/customdomain_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Migration::Schemas::V1::CUSTOMDOMAIN' do
  before(:each) do
    # Re-register the schema since spec_helper resets schemas before each test
    Migration::Schemas.register(:customdomain_v1, Migration::Schemas::V1::CUSTOMDOMAIN)
  end

  let(:valid_customdomain) do
    {
      'display_domain' => 'share.example.com',
      'base_domain' => 'example.com',
      'tld' => 'com',
      'sld' => 'example',
      'custid' => 'user@example.com',
      'subdomain' => 'share',
      'trd' => '',
      'txt_validation_host' => '_onetimesecret.share.example.com',
      'txt_validation_value' => 'ots-verify-abc123def456',
      'verification_status' => 'verified',
      'verified' => 'true',
      'created' => '1706140800.0',
      'updated' => '1706140900.0'
    }
  end

  describe 'valid customdomain' do
    it 'passes validation with all fields' do
      errors = Migration::Schemas.validate(:customdomain_v1, valid_customdomain)

      expect(errors).to be_empty
    end

    it 'passes validation with only required fields' do
      minimal_domain = {
        'display_domain' => 'share.example.com',
        'custid' => 'user@example.com'
      }

      expect(Migration::Schemas.valid?(:customdomain_v1, minimal_domain)).to be true
    end

    it 'allows additional properties' do
      domain_with_extra = valid_customdomain.merge('custom_field' => 'custom_value')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain_with_extra)).to be true
    end
  end

  describe 'display_domain field' do
    it 'fails when display_domain is missing' do
      domain = valid_customdomain.dup
      domain.delete('display_domain')

      errors = Migration::Schemas.validate(:customdomain_v1, domain)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('display_domain') }).to be true
    end

    it 'fails when display_domain is empty string' do
      domain = valid_customdomain.merge('display_domain' => '')

      errors = Migration::Schemas.validate(:customdomain_v1, domain)

      expect(errors).not_to be_empty
    end

    it 'passes with subdomain' do
      domain = valid_customdomain.merge('display_domain' => 'share.example.com')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end

    it 'passes with apex domain' do
      domain = valid_customdomain.merge('display_domain' => 'example.com')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end
  end

  describe 'optional base_domain field' do
    it 'passes when base_domain is absent' do
      domain = valid_customdomain.dup
      domain.delete('base_domain')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end

    it 'passes with valid base_domain' do
      domain = valid_customdomain.merge('base_domain' => 'example.com')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end
  end

  describe 'optional tld field' do
    it 'passes when tld is absent' do
      domain = valid_customdomain.dup
      domain.delete('tld')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end

    it 'passes with standard TLD' do
      domain = valid_customdomain.merge('tld' => 'com')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end

    it 'passes with country code TLD' do
      domain = valid_customdomain.merge('tld' => 'co.uk')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end
  end

  describe 'optional sld field' do
    it 'passes when sld is absent' do
      domain = valid_customdomain.dup
      domain.delete('sld')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end

    it 'passes with valid sld' do
      domain = valid_customdomain.merge('sld' => 'example')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end
  end

  describe 'custid field' do
    it 'fails when custid is missing' do
      domain = valid_customdomain.dup
      domain.delete('custid')

      errors = Migration::Schemas.validate(:customdomain_v1, domain)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('custid') }).to be true
    end

    it 'fails when custid is empty string' do
      domain = valid_customdomain.merge('custid' => '')

      errors = Migration::Schemas.validate(:customdomain_v1, domain)

      expect(errors).not_to be_empty
    end

    it 'passes with email format custid' do
      domain = valid_customdomain.merge('custid' => 'user@example.com')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end
  end

  describe 'optional subdomain field' do
    it 'passes when subdomain is absent' do
      domain = valid_customdomain.dup
      domain.delete('subdomain')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end

    it 'passes with empty subdomain string' do
      domain = valid_customdomain.merge('subdomain' => '')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end

    it 'passes with valid subdomain' do
      domain = valid_customdomain.merge('subdomain' => 'share')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end
  end

  describe 'optional trd field' do
    it 'passes when trd is absent' do
      domain = valid_customdomain.dup
      domain.delete('trd')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end

    it 'passes with empty trd string' do
      domain = valid_customdomain.merge('trd' => '')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end
  end

  describe 'txt_validation fields' do
    it 'passes when txt_validation_host is absent' do
      domain = valid_customdomain.dup
      domain.delete('txt_validation_host')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end

    it 'passes when txt_validation_value is absent' do
      domain = valid_customdomain.dup
      domain.delete('txt_validation_value')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end

    it 'passes with valid txt_validation fields' do
      domain = valid_customdomain.merge(
        'txt_validation_host' => '_onetimesecret.share.example.com',
        'txt_validation_value' => 'ots-verify-abc123'
      )

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end
  end

  describe 'verification fields' do
    it 'passes when verification_status is absent' do
      domain = valid_customdomain.dup
      domain.delete('verification_status')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end

    %w[pending verified failed].each do |valid_status|
      it "passes with verification_status='#{valid_status}'" do
        domain = valid_customdomain.merge('verification_status' => valid_status)

        expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
      end
    end

    it 'fails with invalid verification_status value' do
      domain = valid_customdomain.merge('verification_status' => 'unknown')

      errors = Migration::Schemas.validate(:customdomain_v1, domain)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('verification_status') }).to be true
    end

    it 'passes when verified_at is absent' do
      domain = valid_customdomain.dup
      domain.delete('verified_at')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end

    it 'passes with valid verified_at timestamp' do
      domain = valid_customdomain.merge('verified_at' => '1706140850.0')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end

    it 'fails with invalid verified_at format' do
      domain = valid_customdomain.merge('verified_at' => 'yesterday')

      errors = Migration::Schemas.validate(:customdomain_v1, domain)

      expect(errors).not_to be_empty
    end
  end

  describe 'active field' do
    %w[true false 0 1].each do |valid_value|
      it "passes with active='#{valid_value}'" do
        domain = valid_customdomain.merge('active' => valid_value)

        expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
      end
    end

    it 'fails with non-boolean string' do
      domain = valid_customdomain.merge('active' => 'yes')

      errors = Migration::Schemas.validate(:customdomain_v1, domain)

      expect(errors).not_to be_empty
    end

    it 'passes when active is absent' do
      domain = valid_customdomain.dup
      domain.delete('active')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end
  end

  describe 'verified field' do
    %w[true false 0 1].each do |valid_value|
      it "passes with verified='#{valid_value}'" do
        domain = valid_customdomain.merge('verified' => valid_value)

        expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
      end
    end

    it 'fails with non-boolean string' do
      domain = valid_customdomain.merge('verified' => 'yes')

      errors = Migration::Schemas.validate(:customdomain_v1, domain)

      expect(errors).not_to be_empty
    end

    it 'passes when verified is absent' do
      domain = valid_customdomain.dup
      domain.delete('verified')

      expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
    end
  end

  describe 'timestamp fields' do
    describe 'created timestamp' do
      it 'passes with integer epoch as string' do
        domain = valid_customdomain.merge('created' => '1706140800')

        expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
      end

      it 'passes with float epoch as string' do
        domain = valid_customdomain.merge('created' => '1706140800.123456')

        expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
      end

      it 'fails with non-numeric string' do
        domain = valid_customdomain.merge('created' => 'not-a-number')

        errors = Migration::Schemas.validate(:customdomain_v1, domain)

        expect(errors).not_to be_empty
        expect(errors.any? { |e| e.include?('created') }).to be true
      end

      it 'fails with ISO date format' do
        domain = valid_customdomain.merge('created' => '2024-01-25T00:00:00Z')

        errors = Migration::Schemas.validate(:customdomain_v1, domain)

        expect(errors).not_to be_empty
      end

      it 'fails with empty string' do
        domain = valid_customdomain.merge('created' => '')

        errors = Migration::Schemas.validate(:customdomain_v1, domain)

        expect(errors).not_to be_empty
      end

      it 'passes when created is absent' do
        domain = valid_customdomain.dup
        domain.delete('created')

        expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
      end
    end

    describe 'updated timestamp' do
      it 'passes with valid epoch string' do
        domain = valid_customdomain.merge('updated' => '1706140900.5')

        expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
      end

      it 'fails with invalid format' do
        domain = valid_customdomain.merge('updated' => 'yesterday')

        errors = Migration::Schemas.validate(:customdomain_v1, domain)

        expect(errors).not_to be_empty
      end

      it 'passes when updated is absent' do
        domain = valid_customdomain.dup
        domain.delete('updated')

        expect(Migration::Schemas.valid?(:customdomain_v1, domain)).to be true
      end
    end
  end
end
