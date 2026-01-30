# migrations/2026-01-28/spec/schemas/v1/secret_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Migration::Schemas::V1::SECRET' do
  before(:each) do
    # Re-register the schema since spec_helper resets schemas before each test
    Migration::Schemas.register(:secret_v1, Migration::Schemas::V1::SECRET)
  end

  let(:valid_secret) do
    {
      'key' => 'abc123def456',
      'value' => 'U2FsdGVkX1+abc123encrypteddata==',
      'value_checksum' => 'sha256:abc123',
      'custid' => 'user@example.com',
      'state' => 'new',
      'passphrase' => '1',
      'secret_ttl' => '86400',
      'created' => '1706140800.0',
      'updated' => '1706140900.0',
    }
  end

  describe 'valid secret' do
    it 'passes validation with all fields' do
      errors = Migration::Schemas.validate(:secret_v1, valid_secret)

      expect(errors).to be_empty
    end

    it 'passes validation with only required fields' do
      minimal_secret = { 'key' => 'abc123' }

      expect(Migration::Schemas.valid?(:secret_v1, minimal_secret)).to be true
    end

    it 'allows additional properties' do
      secret_with_extra = valid_secret.merge('custom_field' => 'custom_value')

      expect(Migration::Schemas.valid?(:secret_v1, secret_with_extra)).to be true
    end
  end

  describe 'key field' do
    it 'fails when key is missing' do
      secret = valid_secret.dup
      secret.delete('key')

      errors = Migration::Schemas.validate(:secret_v1, secret)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('key') }).to be true
    end

    it 'fails when key is empty string' do
      secret = valid_secret.merge('key' => '')

      errors = Migration::Schemas.validate(:secret_v1, secret)

      expect(errors).not_to be_empty
    end

    it 'passes with alphanumeric key' do
      secret = valid_secret.merge('key' => 'a1b2c3d4e5f6')

      expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
    end
  end

  describe 'value field (encrypted content)' do
    it 'passes with encrypted value string' do
      secret = valid_secret.merge('value' => 'U2FsdGVkX1+abc123encrypteddata==')

      expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
    end

    it 'passes with empty value string' do
      secret = valid_secret.merge('value' => '')

      expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
    end

    it 'passes when value is absent (optional)' do
      secret = valid_secret.dup
      secret.delete('value')

      expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
    end
  end

  describe 'value_checksum field' do
    it 'passes with valid checksum string' do
      secret = valid_secret.merge('value_checksum' => 'sha256:abc123def456')

      expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
    end

    it 'passes when value_checksum is absent (optional)' do
      secret = valid_secret.dup
      secret.delete('value_checksum')

      expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
    end
  end

  describe 'custid field' do
    it 'passes with email custid' do
      secret = valid_secret.merge('custid' => 'user@example.com')

      expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
    end

    it 'passes with anon custid' do
      secret = valid_secret.merge('custid' => 'anon')

      expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
    end

    it 'passes when custid is absent (optional for anonymous)' do
      secret = valid_secret.dup
      secret.delete('custid')

      expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
    end
  end

  describe 'state field' do
    %w[new viewed received burned].each do |valid_state|
      it "passes with valid state '#{valid_state}'" do
        secret = valid_secret.merge('state' => valid_state)

        expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
      end
    end

    it 'fails with invalid state value' do
      secret = valid_secret.merge('state' => 'deleted')

      errors = Migration::Schemas.validate(:secret_v1, secret)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('state') }).to be true
    end

    it 'fails with state as integer' do
      secret = valid_secret.merge('state' => 1)

      errors = Migration::Schemas.validate(:secret_v1, secret)

      expect(errors).not_to be_empty
    end
  end

  describe 'passphrase field (boolean string)' do
    %w[0 1 true false].each do |valid_value|
      it "passes with passphrase='#{valid_value}'" do
        secret = valid_secret.merge('passphrase' => valid_value)

        expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
      end
    end

    it 'fails with non-boolean string' do
      secret = valid_secret.merge('passphrase' => 'yes')

      errors = Migration::Schemas.validate(:secret_v1, secret)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('passphrase') }).to be true
    end

    it 'passes when passphrase is absent (optional)' do
      secret = valid_secret.dup
      secret.delete('passphrase')

      expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
    end
  end

  describe 'secret_ttl field' do
    it 'passes with integer as string' do
      secret = valid_secret.merge('secret_ttl' => '86400')

      expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
    end

    it 'passes with zero' do
      secret = valid_secret.merge('secret_ttl' => '0')

      expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
    end

    it 'fails with float as string' do
      secret = valid_secret.merge('secret_ttl' => '86400.5')

      errors = Migration::Schemas.validate(:secret_v1, secret)

      expect(errors).not_to be_empty
    end

    it 'fails with non-numeric string' do
      secret = valid_secret.merge('secret_ttl' => '1day')

      errors = Migration::Schemas.validate(:secret_v1, secret)

      expect(errors).not_to be_empty
    end
  end

  describe 'timestamp fields' do
    describe 'created timestamp' do
      it 'passes with integer epoch as string' do
        secret = valid_secret.merge('created' => '1706140800')

        expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
      end

      it 'passes with float epoch as string' do
        secret = valid_secret.merge('created' => '1706140800.123456')

        expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
      end

      it 'fails with non-numeric string' do
        secret = valid_secret.merge('created' => 'not-a-number')

        errors = Migration::Schemas.validate(:secret_v1, secret)

        expect(errors).not_to be_empty
        expect(errors.any? { |e| e.include?('created') }).to be true
      end

      it 'fails with ISO date format' do
        secret = valid_secret.merge('created' => '2024-01-25T00:00:00Z')

        errors = Migration::Schemas.validate(:secret_v1, secret)

        expect(errors).not_to be_empty
      end

      it 'fails with empty string' do
        secret = valid_secret.merge('created' => '')

        errors = Migration::Schemas.validate(:secret_v1, secret)

        expect(errors).not_to be_empty
      end
    end

    describe 'updated timestamp' do
      it 'passes with valid epoch string' do
        secret = valid_secret.merge('updated' => '1706140900.5')

        expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
      end

      it 'fails with invalid format' do
        secret = valid_secret.merge('updated' => 'yesterday')

        errors = Migration::Schemas.validate(:secret_v1, secret)

        expect(errors).not_to be_empty
      end
    end
  end

  describe 'recipient field' do
    it 'passes with email recipient' do
      secret = valid_secret.merge('recipient' => 'recipient@example.com')

      expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
    end

    it 'passes when recipient is absent (optional)' do
      secret = valid_secret.dup
      secret.delete('recipient')

      expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
    end
  end

  describe 'share_domain field' do
    it 'passes with domain value' do
      secret = valid_secret.merge('share_domain' => 'example.com')

      expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
    end

    it 'passes when share_domain is absent (optional)' do
      secret = valid_secret.dup
      secret.delete('share_domain')

      expect(Migration::Schemas.valid?(:secret_v1, secret)).to be true
    end
  end
end
