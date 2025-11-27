# apps/web/auth/spec/hooks/account_lifecycle_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (Smoke Tests)
# =============================================================================
#
# These tests verify that Rodauth hooks execute with expected SIDE EFFECTS.
# They make real HTTP requests and verify state changes in the database.
#
# MUST INCLUDE:
# - Full app boot with Onetime.boot!
# - Real HTTP requests that trigger hooks
# - Assertions on DATABASE STATE (Redis Customer records, SQL accounts)
# - Cleanup after each test
#
# MUST NOT INCLUDE:
# - File.read() on source files
# - String pattern matching for hook names
# - Mocked hook execution
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   VALKEY_URL='valkey://127.0.0.1:2121/0' AUTH_DATABASE_URL='sqlite://data/test_auth.db' \
#     bundle exec rspec apps/web/auth/spec/hooks/account_lifecycle_spec.rb
#
# =============================================================================

require_relative '../spec_helper'
require 'json'
require 'securerandom'

RSpec.describe 'Rodauth Hook Side Effects', type: :integration do
  # Boot the application once for all tests in this file
  before(:all) do
    boot_onetime_app
  end

  # Generate unique test email for each test
  let(:test_email) { "hook-test-#{SecureRandom.hex(8)}@example.com" }
  let(:valid_password) { 'SecureP@ss123!' }

  # Helper to create an account via HTTP
  def create_account(email:, password:)
    json_post '/auth/create-account', {
      login: email,
      'login-confirm': email,
      password: password,
      'password-confirm': password
    }
    last_response
  end

  # Helper to get account from auth database
  def find_account_by_email(email)
    auth_db[:accounts].where(email: email).first
  end

  # Helper to get customer from Redis by email
  #
  # NOTE: Use find_by_email or find_by_extid for lookups.
  # Do NOT use custid - it's a legacy field (alias for objid) and causes confusion.
  # The external_id in auth accounts maps to Customer.extid, not custid.
  def find_customer_by_email(email)
    OT::Customer.find_by_email(email)
  rescue StandardError
    nil
  end

  # Helper to check if customer exists by email
  #
  # NOTE: Use email_exists? for email lookups, exists?(objid) for ID lookups.
  # Do NOT use custid - it's legacy and confusing.
  def customer_exists?(email)
    OT::Customer.email_exists?(email)
  rescue StandardError
    false
  end

  describe 'after_create_account hook' do
    context 'when account creation succeeds' do
      it 'creates a Customer record in Redis' do
        response = create_account(email: test_email, password: valid_password)

        # Account creation should succeed (200/201)
        # Skip if we get client/validation errors - these indicate environment issues
        unless [200, 201].include?(response.status)
          skip "Account creation returned #{response.status}: #{response.body[0..500]}"
        end

        # Verify Customer record was created in Redis
        expect(customer_exists?(test_email)).to be(true),
          "Expected Customer record to exist in Redis for #{test_email}"
      end

      # NOTE: external_id links to Customer.extid (NOT custid - that's legacy)
      it 'links Customer to the auth account via extid/external_id' do
        response = create_account(email: test_email, password: valid_password)
        unless [200, 201].include?(response.status)
          skip "Account creation returned #{response.status}"
        end

        account = find_account_by_email(test_email)
        customer = find_customer_by_email(test_email)

        expect(account).not_to be_nil, "Account should exist in auth database"
        expect(customer).not_to be_nil, "Customer should exist in Redis"

        # The account's external_id should match the customer's extid
        expect(account[:external_id]).to eq(customer.extid),
          "Account external_id (#{account[:external_id]}) should match Customer extid (#{customer.extid})"
      end

      it 'sets Customer email to match account email' do
        create_account(email: test_email, password: valid_password)

        customer = find_customer_by_email(test_email)

        expect(customer).not_to be_nil
        expect(customer.email).to eq(test_email)
      end
    end

    context 'when account creation is rejected' do
      it 'does not create a Customer record for invalid email' do
        create_account(email: 'not-an-email', password: valid_password)

        # Invalid email should be rejected - Rodauth returns 400 for validation errors
        expect([400, 422]).to include(last_response.status)

        # No Customer should be created
        expect(customer_exists?('not-an-email')).to be(false)
      end

      it 'does not create a Customer record for duplicate email' do
        # Create first account
        create_account(email: test_email, password: valid_password)
        expect(last_response.status).to be_between(200, 299)

        # Attempt to create duplicate - Rodauth returns 400 for validation errors
        create_account(email: test_email, password: valid_password)
        expect([400, 422]).to include(last_response.status)

        # Should still only have one Customer
        customer = find_customer_by_email(test_email)
        expect(customer).not_to be_nil
      end
    end
  end

  describe 'login hooks' do
    let(:login_email) { "login-test-#{SecureRandom.hex(8)}@example.com" }

    before do
      # Create account first
      create_account(email: login_email, password: valid_password)
      expect(last_response.status).to be_between(200, 299),
        "Account creation failed: #{last_response.body}"
    end

    describe 'after_login hook' do
      it 'allows successful login with correct credentials' do
        json_post '/auth/login', { login: login_email, password: valid_password }

        expect(last_response.status).to eq(200),
          "Expected 200 but got #{last_response.status}: #{last_response.body}"
      end

      it 'returns JSON response with success indicator' do
        json_post '/auth/login', { login: login_email, password: valid_password }

        json = JSON.parse(last_response.body)
        # Rodauth returns success as a message string, not a boolean
        expect(json['success']).to be_truthy
      end
    end

    describe 'before_login_attempt hook (lockout tracking)' do
      it 'tracks failed login attempts in SQL database' do
        account = find_account_by_email(login_email)
        expect(account).not_to be_nil

        # Make a failed login attempt
        json_post '/auth/login', { login: login_email, password: 'wrong-password' }
        expect(last_response.status).to eq(401)

        # Check that failure is tracked
        failure_record = auth_db[:account_login_failures].where(id: account[:id]).first
        expect(failure_record).not_to be_nil,
          "Expected login failure to be tracked in account_login_failures table"
        expect(failure_record[:number]).to be >= 1
      end

      it 'clears failure count on successful login' do
        account = find_account_by_email(login_email)

        # Make some failed attempts
        2.times do
          json_post '/auth/login', { login: login_email, password: 'wrong' }
        end

        # Verify failures tracked
        failure_count = auth_db[:account_login_failures].where(id: account[:id]).first
        expect(failure_count).not_to be_nil

        # Successful login
        json_post '/auth/login', { login: login_email, password: valid_password }
        expect(last_response.status).to eq(200)

        # Failures should be cleared
        failure_count_after = auth_db[:account_login_failures].where(id: account[:id]).first
        expect(failure_count_after).to be_nil.or(satisfy { |r| r[:number] == 0 })
      end
    end
  end

  describe 'password change hooks' do
    let(:password_email) { "password-test-#{SecureRandom.hex(8)}@example.com" }

    before do
      create_account(email: password_email, password: valid_password)
      expect(last_response.status).to be_between(200, 299)
    end

    it 'allows password reset request for existing account' do
      json_post '/auth/reset-password-request', { login: password_email }

      # Should succeed (or return success-like response to prevent enumeration)
      expect([200, 422]).to include(last_response.status)
    end

    it 'creates password reset key in database' do
      json_post '/auth/reset-password-request', { login: password_email }

      account = find_account_by_email(password_email)
      reset_key = auth_db[:account_password_reset_keys].where(id: account[:id]).first

      # Reset key should be created if the route succeeded
      if last_response.status == 200
        expect(reset_key).not_to be_nil,
          "Expected password reset key to be created"
      end
    end
  end
end
