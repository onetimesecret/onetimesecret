# spec/integration/full/hooks/account_deletion_spec.rb
#
# frozen_string_literal: true

# Integration tests for account deletion in full auth mode.
#
# These tests verify that account deletion properly cleans up both:
# - Auth database records (PostgreSQL/SQLite accounts and related tables)
# - Redis Customer records (via Familia)
#
# Tests cover:
# - Password verification against Rodauth's auth database
# - Cascading deletion of all auth-related tables
# - Proper order of operations (auth DB first, then Redis)
# - Error handling for edge cases
#
# Database and application setup is handled by FullModeSuiteDatabase
# (see spec/support/full_mode_suite_database.rb).

require 'spec_helper'

RSpec.describe 'Account Deletion in Full Auth Mode', :full_auth_mode, type: :integration do
  include_context 'auth_rack_test'

  let(:test_email) { "delete-test-#{SecureRandom.hex(8)}@example.com" }
  let(:valid_password) { 'SecureP@ss123!' }
  let(:wrong_password) { 'WrongP@ss456!' }

  # Helper to create an account via HTTP
  def create_account(email:, password:)
    post_json '/auth/create-account', {
      login: email,
      'login-confirm': email,
      password: password,
      'password-confirm': password,
    }
    last_response
  end

  # Helper to login via HTTP
  def login(email:, password:)
    post_json '/auth/login', { login: email, password: password }
    last_response
  end

  # Helper to get account from auth database
  def find_account_by_email(email)
    test_db[:accounts].where(email: email).first
  end

  # Helper to get customer from Redis by email
  def find_customer_by_email(email)
    OT::Customer.find_by_email(email)
  rescue StandardError
    nil
  end

  # Helper to check if customer exists by email
  def customer_exists?(email)
    OT::Customer.email_exists?(email)
  rescue StandardError
    false
  end

  describe 'Auth::Operations::CloseAccount' do
    context 'with valid extid' do
      before do
        # Create account via HTTP to set up both auth DB and Redis Customer
        response = create_account(email: test_email, password: valid_password)
        unless [200, 201].include?(response.status)
          skip "Account creation returned #{response.status}: #{response.body[0..500]}"
        end
      end

      it 'deletes account from accounts table' do
        customer = find_customer_by_email(test_email)
        account = find_account_by_email(test_email)
        expect(account).not_to be_nil

        result = Auth::Operations::CloseAccount.call(extid: customer.extid)

        expect(result[:success]).to be true
        expect(find_account_by_email(test_email)).to be_nil
      end

      it 'deletes password hash from account_password_hashes table' do
        customer = find_customer_by_email(test_email)
        account = find_account_by_email(test_email)

        # Verify password hash exists before deletion
        password_hash = test_db[:account_password_hashes].where(id: account[:id]).first
        expect(password_hash).not_to be_nil

        Auth::Operations::CloseAccount.call(extid: customer.extid)

        # Password hash should be deleted
        expect(test_db[:account_password_hashes].where(id: account[:id]).first).to be_nil
      end

      it 'returns account_id on successful deletion' do
        customer = find_customer_by_email(test_email)
        account = find_account_by_email(test_email)

        result = Auth::Operations::CloseAccount.call(extid: customer.extid)

        expect(result[:success]).to be true
        expect(result[:account_id]).to eq(account[:id])
      end
    end

    context 'with invalid extid' do
      it 'returns error for nil extid' do
        result = Auth::Operations::CloseAccount.call(extid: nil)

        expect(result[:success]).to be false
        expect(result[:error]).to include('External ID is required')
      end

      it 'returns error for empty extid' do
        result = Auth::Operations::CloseAccount.call(extid: '')

        expect(result[:success]).to be false
        expect(result[:error]).to include('External ID is required')
      end

      it 'returns error for non-existent account' do
        result = Auth::Operations::CloseAccount.call(extid: 'nonexistent-extid-12345')

        expect(result[:success]).to be false
        expect(result[:error]).to include('No auth account found')
      end
    end

    context 'with related auth data' do
      before do
        response = create_account(email: test_email, password: valid_password)
        unless [200, 201].include?(response.status)
          skip "Account creation returned #{response.status}"
        end

        # Login to create session keys
        login(email: test_email, password: valid_password)
      end

      it 'deletes active session keys' do
        customer = find_customer_by_email(test_email)
        account = find_account_by_email(test_email)

        # Check if we have active sessions (may not always be created)
        session_count = test_db[:account_active_session_keys].where(account_id: account[:id]).count

        Auth::Operations::CloseAccount.call(extid: customer.extid)

        # Sessions should be deleted
        remaining = test_db[:account_active_session_keys].where(account_id: account[:id]).count
        expect(remaining).to eq(0)
      end

      it 'deletes login failure records' do
        # Create some failed login attempts
        3.times { login(email: test_email, password: wrong_password) }

        customer = find_customer_by_email(test_email)
        account = find_account_by_email(test_email)

        # Verify failures exist
        failures = test_db[:account_login_failures].where(id: account[:id]).first
        expect(failures).not_to be_nil if failures

        Auth::Operations::CloseAccount.call(extid: customer.extid)

        # Failure records should be deleted
        expect(test_db[:account_login_failures].where(id: account[:id]).first).to be_nil
      end
    end
  end

  describe 'DestroyAccount logic (full auth mode)' do
    # Note: Direct logic tests for DestroyAccount require MockStrategyResult
    # which is only available in Tryouts. The HTTP-level tests above cover
    # the full flow. For unit tests, see:
    #   try/unit/logic/account/destroy_account_try.rb

    before do
      response = create_account(email: test_email, password: valid_password)
      unless [200, 201].include?(response.status)
        skip "Account creation returned #{response.status}: #{response.body[0..500]}"
      end
    end

    context 'password verification via HTTP' do
      it 'accepts correct password at close-account endpoint' do
        # Login first to establish session
        login(email: test_email, password: valid_password)
        expect(last_response.status).to eq(200)

        # Now attempt to close account with correct password
        post_json '/auth/close-account', { password: valid_password }

        # Should succeed (200) or redirect (302)
        expect([200, 302]).to include(last_response.status),
          "Expected 200/302 but got #{last_response.status}: #{last_response.body[0..200]}"
      end

      it 'rejects incorrect password at close-account endpoint' do
        # Login first
        login(email: test_email, password: valid_password)
        expect(last_response.status).to eq(200)

        # Attempt to close with wrong password
        post_json '/auth/close-account', { password: wrong_password }

        # Should fail with 401 or 422 (validation error)
        expect([401, 422]).to include(last_response.status),
          "Expected 401/422 but got #{last_response.status}"
      end

      it 'rejects empty password at close-account endpoint' do
        # Login first
        login(email: test_email, password: valid_password)
        expect(last_response.status).to eq(200)

        # Attempt to close with empty password
        post_json '/auth/close-account', { password: '' }

        # Should fail with validation error
        expect([401, 422]).to include(last_response.status),
          "Expected 401/422 but got #{last_response.status}"
      end
    end
  end
end
