# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Migration::Schemas::V1::CUSTOMER' do
  before(:each) do
    # Re-register the schema since spec_helper resets schemas before each test
    Migration::Schemas.register(:customer_v1, Migration::Schemas::V1::CUSTOMER)
  end

  let(:valid_customer) do
    {
      'custid' => 'user@example.com',
      'email' => 'user@example.com',
      'created' => '1706140800.0',
      'updated' => '1706140900.0',
      'role' => 'customer',
      'verified' => 'true',
      'planid' => 'pro',
      'stripe_customer_id' => 'cus_123abc',
      'stripe_subscription_id' => 'sub_456def',
      'locale' => 'en',
      'apitoken' => 'token123',
      'passphrase' => 'hashed_passphrase',
      'last_login' => '1706141000.0',
      'secrets_created' => '42',
      'active' => 'true'
    }
  end

  describe 'valid customer' do
    it 'passes validation with all fields' do
      errors = Migration::Schemas.validate(:customer_v1, valid_customer)

      expect(errors).to be_empty
    end

    it 'passes validation with only required fields' do
      minimal_customer = { 'custid' => 'minimal@example.com' }

      expect(Migration::Schemas.valid?(:customer_v1, minimal_customer)).to be true
    end

    it 'allows additional properties' do
      customer_with_extra = valid_customer.merge('custom_field' => 'custom_value')

      expect(Migration::Schemas.valid?(:customer_v1, customer_with_extra)).to be true
    end
  end

  describe 'custid field' do
    it 'fails when custid is missing' do
      customer = valid_customer.dup
      customer.delete('custid')

      errors = Migration::Schemas.validate(:customer_v1, customer)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('custid') }).to be true
    end

    it 'fails when custid is empty string' do
      customer = valid_customer.merge('custid' => '')

      errors = Migration::Schemas.validate(:customer_v1, customer)

      expect(errors).not_to be_empty
    end
  end

  describe 'role field' do
    %w[customer colonel recipient anonymous].each do |valid_role|
      it "passes with valid role '#{valid_role}'" do
        customer = valid_customer.merge('role' => valid_role)

        expect(Migration::Schemas.valid?(:customer_v1, customer)).to be true
      end
    end

    it 'fails with invalid role value' do
      customer = valid_customer.merge('role' => 'admin')

      errors = Migration::Schemas.validate(:customer_v1, customer)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('role') }).to be true
    end

    it 'fails with role as integer' do
      customer = valid_customer.merge('role' => 1)

      errors = Migration::Schemas.validate(:customer_v1, customer)

      expect(errors).not_to be_empty
    end
  end

  describe 'timestamp fields' do
    describe 'created timestamp' do
      it 'passes with integer epoch as string' do
        customer = valid_customer.merge('created' => '1706140800')

        expect(Migration::Schemas.valid?(:customer_v1, customer)).to be true
      end

      it 'passes with float epoch as string' do
        customer = valid_customer.merge('created' => '1706140800.123456')

        expect(Migration::Schemas.valid?(:customer_v1, customer)).to be true
      end

      it 'fails with non-numeric string' do
        customer = valid_customer.merge('created' => 'not-a-number')

        errors = Migration::Schemas.validate(:customer_v1, customer)

        expect(errors).not_to be_empty
        expect(errors.any? { |e| e.include?('created') }).to be true
      end

      it 'fails with ISO date format' do
        customer = valid_customer.merge('created' => '2024-01-25T00:00:00Z')

        errors = Migration::Schemas.validate(:customer_v1, customer)

        expect(errors).not_to be_empty
      end

      it 'fails with empty string' do
        customer = valid_customer.merge('created' => '')

        errors = Migration::Schemas.validate(:customer_v1, customer)

        expect(errors).not_to be_empty
      end
    end

    describe 'updated timestamp' do
      it 'passes with valid epoch string' do
        customer = valid_customer.merge('updated' => '1706140900.5')

        expect(Migration::Schemas.valid?(:customer_v1, customer)).to be true
      end

      it 'fails with invalid format' do
        customer = valid_customer.merge('updated' => 'yesterday')

        errors = Migration::Schemas.validate(:customer_v1, customer)

        expect(errors).not_to be_empty
      end
    end

    describe 'last_login timestamp' do
      it 'passes with valid epoch string' do
        customer = valid_customer.merge('last_login' => '1706141000.0')

        expect(Migration::Schemas.valid?(:customer_v1, customer)).to be true
      end

      it 'fails with invalid format' do
        customer = valid_customer.merge('last_login' => 'never')

        errors = Migration::Schemas.validate(:customer_v1, customer)

        expect(errors).not_to be_empty
      end
    end
  end

  describe 'Stripe customer ID' do
    it 'passes with valid cus_ prefix' do
      customer = valid_customer.merge('stripe_customer_id' => 'cus_abc123xyz')

      expect(Migration::Schemas.valid?(:customer_v1, customer)).to be true
    end

    it 'fails without cus_ prefix' do
      customer = valid_customer.merge('stripe_customer_id' => 'abc123xyz')

      errors = Migration::Schemas.validate(:customer_v1, customer)

      expect(errors).not_to be_empty
      expect(errors.any? { |e| e.include?('stripe_customer_id') }).to be true
    end

    it 'fails with wrong prefix' do
      customer = valid_customer.merge('stripe_customer_id' => 'sub_abc123xyz')

      errors = Migration::Schemas.validate(:customer_v1, customer)

      expect(errors).not_to be_empty
    end

    it 'passes when stripe_customer_id is absent' do
      customer = valid_customer.dup
      customer.delete('stripe_customer_id')

      expect(Migration::Schemas.valid?(:customer_v1, customer)).to be true
    end
  end

  describe 'Stripe subscription ID' do
    it 'passes with valid sub_ prefix' do
      customer = valid_customer.merge('stripe_subscription_id' => 'sub_xyz789')

      expect(Migration::Schemas.valid?(:customer_v1, customer)).to be true
    end

    it 'fails without sub_ prefix' do
      customer = valid_customer.merge('stripe_subscription_id' => 'xyz789')

      errors = Migration::Schemas.validate(:customer_v1, customer)

      expect(errors).not_to be_empty
    end
  end

  describe 'verified field' do
    %w[true false 0 1].each do |valid_value|
      it "passes with verified='#{valid_value}'" do
        customer = valid_customer.merge('verified' => valid_value)

        expect(Migration::Schemas.valid?(:customer_v1, customer)).to be true
      end
    end

    it 'fails with non-boolean string' do
      customer = valid_customer.merge('verified' => 'yes')

      errors = Migration::Schemas.validate(:customer_v1, customer)

      expect(errors).not_to be_empty
    end
  end

  describe 'active field' do
    %w[true false 0 1].each do |valid_value|
      it "passes with active='#{valid_value}'" do
        customer = valid_customer.merge('active' => valid_value)

        expect(Migration::Schemas.valid?(:customer_v1, customer)).to be true
      end
    end
  end

  describe 'secrets_created field' do
    it 'passes with integer as string' do
      customer = valid_customer.merge('secrets_created' => '100')

      expect(Migration::Schemas.valid?(:customer_v1, customer)).to be true
    end

    it 'passes with zero' do
      customer = valid_customer.merge('secrets_created' => '0')

      expect(Migration::Schemas.valid?(:customer_v1, customer)).to be true
    end

    it 'fails with float as string' do
      customer = valid_customer.merge('secrets_created' => '10.5')

      errors = Migration::Schemas.validate(:customer_v1, customer)

      expect(errors).not_to be_empty
    end

    it 'fails with non-numeric string' do
      customer = valid_customer.merge('secrets_created' => 'many')

      errors = Migration::Schemas.validate(:customer_v1, customer)

      expect(errors).not_to be_empty
    end
  end
end
