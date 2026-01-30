# migrations/2026-01-28/spec/schemas/v1/metadata_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Migration::Schemas::V1::METADATA' do
  before(:each) do
    # Re-register the schema since spec_helper resets schemas before each test
    Migration::Schemas.register(:metadata_v1, Migration::Schemas::V1::METADATA)
  end

  let(:valid_metadata) do
    {
      'key' => 'abc123xyz',
      'custid' => 'user@example.com',
      'state' => 'new',
      'secret_shortkey' => 'xyz789',
      'recipients' => 'recipient@example.com',
      'share_domain' => 'custom.example.com',
      'created' => '1706140800.0',
      'updated' => '1706140900.0'
    }
  end

  describe 'valid metadata' do
    it 'passes validation with all fields' do
      errors = Migration::Schemas.validate(:metadata_v1, valid_metadata)

      expect(errors).to be_empty
    end

    it 'passes validation with only required fields' do
      minimal_metadata = { 'key' => 'secretkey123' }

      expect(Migration::Schemas.valid?(:metadata_v1, minimal_metadata)).to be true
    end

    it 'allows additional properties' do
      metadata_with_extra = valid_metadata.merge('custom_field' => 'custom_value')

      expect(Migration::Schemas.valid?(:metadata_v1, metadata_with_extra)).to be true
    end
  end

  describe 'key field' do
    it 'fails when key is missing' do
      metadata = valid_metadata.dup
      metadata.delete('key')

      errors = Migration::Schemas.validate(:metadata_v1, metadata)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('key') }).to be true
    end

    it 'fails when key is empty string' do
      metadata = valid_metadata.merge('key' => '')

      errors = Migration::Schemas.validate(:metadata_v1, metadata)

      expect(errors).not_to be_empty
    end

    it 'passes with alphanumeric key' do
      metadata = valid_metadata.merge('key' => 'abc123XYZ789')

      expect(Migration::Schemas.valid?(:metadata_v1, metadata)).to be true
    end
  end

  describe 'custid field' do
    it 'passes when custid is present' do
      metadata = valid_metadata.merge('custid' => 'alice@example.com')

      expect(Migration::Schemas.valid?(:metadata_v1, metadata)).to be true
    end

    it 'passes when custid is absent (anonymous secret)' do
      metadata = valid_metadata.dup
      metadata.delete('custid')

      expect(Migration::Schemas.valid?(:metadata_v1, metadata)).to be true
    end

    it 'passes with email format custid' do
      metadata = valid_metadata.merge('custid' => 'user+tag@sub.example.com')

      expect(Migration::Schemas.valid?(:metadata_v1, metadata)).to be true
    end
  end

  describe 'state field' do
    %w[new viewed received burned].each do |valid_state|
      it "passes with valid state '#{valid_state}'" do
        metadata = valid_metadata.merge('state' => valid_state)

        expect(Migration::Schemas.valid?(:metadata_v1, metadata)).to be true
      end
    end

    it 'fails with invalid state value' do
      metadata = valid_metadata.merge('state' => 'deleted')

      errors = Migration::Schemas.validate(:metadata_v1, metadata)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('state') }).to be true
    end

    it 'fails with state as integer' do
      metadata = valid_metadata.merge('state' => 1)

      errors = Migration::Schemas.validate(:metadata_v1, metadata)

      expect(errors).not_to be_empty
    end

    it 'passes when state is absent' do
      metadata = valid_metadata.dup
      metadata.delete('state')

      expect(Migration::Schemas.valid?(:metadata_v1, metadata)).to be true
    end
  end

  describe 'secret_shortkey field' do
    it 'passes with alphanumeric shortkey' do
      metadata = valid_metadata.merge('secret_shortkey' => 'abc123')

      expect(Migration::Schemas.valid?(:metadata_v1, metadata)).to be true
    end

    it 'passes when secret_shortkey is absent' do
      metadata = valid_metadata.dup
      metadata.delete('secret_shortkey')

      expect(Migration::Schemas.valid?(:metadata_v1, metadata)).to be true
    end
  end

  describe 'recipients field' do
    it 'passes with single recipient' do
      metadata = valid_metadata.merge('recipients' => 'recipient@example.com')

      expect(Migration::Schemas.valid?(:metadata_v1, metadata)).to be true
    end

    it 'passes with comma-separated recipients' do
      metadata = valid_metadata.merge('recipients' => 'a@example.com,b@example.com')

      expect(Migration::Schemas.valid?(:metadata_v1, metadata)).to be true
    end

    it 'passes when recipients is absent' do
      metadata = valid_metadata.dup
      metadata.delete('recipients')

      expect(Migration::Schemas.valid?(:metadata_v1, metadata)).to be true
    end
  end

  describe 'share_domain field' do
    it 'passes with valid domain' do
      metadata = valid_metadata.merge('share_domain' => 'secrets.example.com')

      expect(Migration::Schemas.valid?(:metadata_v1, metadata)).to be true
    end

    it 'passes when share_domain is absent' do
      metadata = valid_metadata.dup
      metadata.delete('share_domain')

      expect(Migration::Schemas.valid?(:metadata_v1, metadata)).to be true
    end
  end

  describe 'timestamp fields' do
    describe 'created timestamp' do
      it 'passes with integer epoch as string' do
        metadata = valid_metadata.merge('created' => '1706140800')

        expect(Migration::Schemas.valid?(:metadata_v1, metadata)).to be true
      end

      it 'passes with float epoch as string' do
        metadata = valid_metadata.merge('created' => '1706140800.123456')

        expect(Migration::Schemas.valid?(:metadata_v1, metadata)).to be true
      end

      it 'fails with non-numeric string' do
        metadata = valid_metadata.merge('created' => 'not-a-number')

        errors = Migration::Schemas.validate(:metadata_v1, metadata)

        expect(errors).not_to be_empty
        expect(errors.any? { |e| e.include?('created') }).to be true
      end

      it 'fails with ISO date format' do
        metadata = valid_metadata.merge('created' => '2024-01-25T00:00:00Z')

        errors = Migration::Schemas.validate(:metadata_v1, metadata)

        expect(errors).not_to be_empty
      end

      it 'fails with empty string' do
        metadata = valid_metadata.merge('created' => '')

        errors = Migration::Schemas.validate(:metadata_v1, metadata)

        expect(errors).not_to be_empty
      end
    end

    describe 'updated timestamp' do
      it 'passes with valid epoch string' do
        metadata = valid_metadata.merge('updated' => '1706140900.5')

        expect(Migration::Schemas.valid?(:metadata_v1, metadata)).to be true
      end

      it 'fails with invalid format' do
        metadata = valid_metadata.merge('updated' => 'yesterday')

        errors = Migration::Schemas.validate(:metadata_v1, metadata)

        expect(errors).not_to be_empty
      end
    end
  end

  describe 'anonymous secrets' do
    it 'passes validation for anonymous secret (no custid)' do
      anonymous_metadata = {
        'key' => 'anon123secret',
        'state' => 'new',
        'created' => '1706140800.0'
      }

      expect(Migration::Schemas.valid?(:metadata_v1, anonymous_metadata)).to be true
    end

    it 'passes validation with minimal anonymous secret' do
      minimal_anon = { 'key' => 'minimalkey' }

      expect(Migration::Schemas.valid?(:metadata_v1, minimal_anon)).to be true
    end
  end
end
