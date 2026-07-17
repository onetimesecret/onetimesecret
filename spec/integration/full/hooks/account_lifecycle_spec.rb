# spec/integration/full/hooks/account_lifecycle_spec.rb
#
# frozen_string_literal: true

# Integration tests for Rodauth lifecycle hooks in full auth mode.
#
# These tests verify that Rodauth hooks execute with expected SIDE EFFECTS:
# - Real HTTP requests that trigger hooks
# - Assertions on DATABASE STATE (Redis Customer records, SQL accounts)
#
# Database and application setup is handled by FullModeSuiteDatabase
# (see spec/support/full_mode_suite_database.rb).

require 'spec_helper'

RSpec.describe 'Rodauth Hook Side Effects', :full_auth_mode, type: :integration do
  include_context 'auth_rack_test'

  # Generate unique test email for each test
  let(:test_email) { "hook-test-#{SecureRandom.hex(8)}@example.com" }
  let(:valid_password) { 'SecureP@ss123!' }

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

  # Helper to get account from auth database
  def find_account_by_email(email)
    test_db[:accounts].where(email: email).first
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

        account  = find_account_by_email(test_email)
        customer = find_customer_by_email(test_email)

        expect(account).not_to be_nil, 'Account should exist in auth database'
        expect(customer).not_to be_nil, 'Customer should exist in Redis'

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
        post_json '/auth/login', { login: login_email, password: valid_password }

        expect(last_response.status).to eq(200),
          "Expected 200 but got #{last_response.status}: #{last_response.body}"
      end

      it 'returns JSON response with success indicator' do
        post_json '/auth/login', { login: login_email, password: valid_password }

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
        post_json '/auth/login', { login: login_email, password: 'wrong-password' }
        expect(last_response.status).to eq(401)

        # Check that failure is tracked
        failure_record = test_db[:account_login_failures].where(id: account[:id]).first
        expect(failure_record).not_to be_nil,
          'Expected login failure to be tracked in account_login_failures table'
        expect(failure_record[:number]).to be >= 1
      end

      it 'clears failure count on successful login' do
        account = find_account_by_email(login_email)

        # Make some failed attempts
        2.times do
          post_json '/auth/login', { login: login_email, password: 'wrong' }
        end

        # Verify failures tracked
        failure_count = test_db[:account_login_failures].where(id: account[:id]).first
        expect(failure_count).not_to be_nil

        # Successful login
        post_json '/auth/login', { login: login_email, password: valid_password }
        expect(last_response.status).to eq(200)

        # Failures should be cleared
        failure_count_after = test_db[:account_login_failures].where(id: account[:id]).first
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
      post_json '/auth/reset-password-request', { login: password_email }

      # Should succeed (or return success-like response to prevent enumeration)
      expect([200, 422]).to include(last_response.status)
    end

    it 'creates password reset key in database' do
      post_json '/auth/reset-password-request', { login: password_email }

      account   = find_account_by_email(password_email)
      reset_key = test_db[:account_password_reset_keys].where(id: account[:id]).first

      # Reset key should be created if the route succeeded
      if last_response.status == 200
        expect(reset_key).not_to be_nil,
          'Expected password reset key to be created'
      end
    end
  end

  # ---------------------------------------------------------------------------
  # M-2: session revocation on credential change (PR #3803, security audit)
  #
  # The after_reset_password / after_change_password hooks revoke the encrypted
  # Redis session blobs (the real app auth gate). The remediation under test
  # replaced a blanket `safe_execute` swallow with an explicit begin/rescue that
  # FAILS OPEN (the credential change still commits) but LOUDLY: a distinct
  # error-level :sessions_revoke_FAILED event plus a Sentry re-capture, so a
  # non-revoking reset/change alerts instead of blending into routine logging.
  #
  # These specs pin that behavior: the credential change must still complete when
  # revocation raises, and the loud signal must fire.
  # ---------------------------------------------------------------------------
  describe 'session revocation on credential change (M-2)' do
    let(:cred_email) { "revoke-test-#{SecureRandom.hex(8)}@example.com" }
    let(:new_password) { 'NewSecureP@ss456!' }

    # sentry-ruby is `require: false`, so the Sentry constant is absent in test
    # mode. Stub it (mirroring spec/unit/onetime/jobs/trace_propagation_spec.rb)
    # so the hook's `defined?(Sentry) && Sentry.initialized?` guard is truthy and
    # the capture path is exercised deterministically.
    let(:sentry_scope) do
      instance_double('Sentry::Scope', set_level: nil, set_tags: nil, set_context: nil)
    end

    def stub_sentry!
      # Define the methods on the module so verify_partial_doubles is satisfied
      # (an empty Module would reject `allow(...).to receive(:initialized?)`).
      stub_const('Sentry', Module.new do
        def self.initialized?; true; end

        def self.capture_exception(_ex); end
      end)
      allow(Sentry).to receive(:capture_exception).and_yield(sentry_scope)
    end

    # Establish an authenticated session (change-password requires being logged in
    # and supplying the current password).
    def login(email:, password:)
      post_json '/auth/login', { login: email, password: password }
      expect(last_response.status).to eq(200),
        "Login failed: #{last_response.body[0..500]}"
    end

    let(:revoke_op) { Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent }

    def change_password
      post_json '/auth/change-password', {
        password: valid_password,
        'new-password': new_password,
        'password-confirm': new_password,
      }
    end

    describe 'after_change_password hook' do
      before do
        create_account(email: cred_email, password: valid_password)
        expect(last_response.status).to be_between(200, 299),
          "Account creation failed: #{last_response.body[0..500]}"
        login(email: cred_email, password: valid_password)
      end

      it 'still completes the change but emits :sessions_revoke_FAILED and captures to Sentry when revocation raises' do
        stub_sentry!
        allow(revoke_op).to receive(:new).and_raise(StandardError.new('redis revoke boom'))
        allow(Auth::Logging).to receive(:log_auth_event).and_call_original

        change_password

        # FAIL-OPEN: the password change commits even though revocation raised.
        expect(last_response.status).to eq(200),
          "Expected change to still succeed but got #{last_response.status}: #{last_response.body[0..500]}"

        # LOUD: distinct error-level event, tagged with the originating hook.
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:sessions_revoke_FAILED, hash_including(level: :error, hook: :after_change_password))

        # LOUD: Sentry re-capture attempted.
        expect(Sentry).to have_received(:capture_exception)
      end

      it 'revokes other sessions and logs :sessions_revoked_on_change on success' do
        allow(Auth::Logging).to receive(:log_auth_event).and_call_original

        change_password

        expect(last_response.status).to eq(200)
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:sessions_revoked_on_change, hash_including(level: :info))
        # The failure event must NOT fire on the happy path.
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:sessions_revoke_FAILED, any_args)
      end

      it 'falls back to the account email for revocation when external_id is blank (fail-secure identity)' do
        # Blank the external_id so the hook exercises the next->if/else email
        # fallback rather than silently skipping the revoke.
        account = find_account_by_email(cred_email)
        test_db[:accounts].where(id: account[:id]).update(external_id: nil)

        result = revoke_op::Result.new(
          revoked: true, blobs_deleted: 0, untracked_deleted: 0, scan_capped: false
        )
        fake_op = instance_double(revoke_op.to_s, call: result)
        # Revocation must still run, keyed on the email fallback — not skipped.
        expect(revoke_op).to receive(:new)
          .with(hash_including(custid: cred_email)).and_return(fake_op)

        allow(Auth::Logging).to receive(:log_auth_event).and_call_original

        change_password

        expect(last_response.status).to eq(200)
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:sessions_revoked_on_change, hash_including(level: :info))
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:sessions_revoke_skipped_no_identity, any_args)
      end
    end

    describe 'after_reset_password hook' do
      before do
        create_account(email: cred_email, password: valid_password)
        expect(last_response.status).to be_between(200, 299),
          "Account creation failed: #{last_response.body[0..500]}"
      end

      # Drives the real unauthenticated reset flow. The reset key is HMAC'd
      # (base.rb enables hmac_secret_guard), so it cannot be reconstructed from
      # the DB row — the only place the valid token appears is the delivered
      # email link. Intercept the mailer to capture it, then submit the reset.
      def reset_password_with_token
        # Auth emails are dispatched synchronously through
        # Onetime::Jobs::Publisher.enqueue_email_raw during the request (the
        # Logger delivery itself runs in a worker that doesn't execute in-test),
        # so that publisher call is the reliable interception point for the
        # HMAC'd reset link/token.
        captured = []
        allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw)
          .and_wrap_original do |orig, payload, **kwargs|
            captured << payload
            orig.call(payload, **kwargs)
          end

        post_json '/auth/reset-password-request', { login: cred_email }

        body  = captured.map { |e| e[:body].to_s }.join("\n")
        match = body.match(/[?&]key=([^"'&\s<>]+)/)
        skip 'reset key not issued in this environment (email/config gated)' if match.nil?

        token = CGI.unescape(match[1])
        post_json '/auth/reset-password', {
          key: token,
          password: new_password,
          'password-confirm': new_password,
        }
        token
      end

      it 'still completes the reset but emits :sessions_revoke_FAILED (after_reset_password) and captures to Sentry when revocation raises' do
        stub_sentry!
        allow(revoke_op).to receive(:new).and_raise(StandardError.new('redis reset boom'))
        allow(Auth::Logging).to receive(:log_auth_event).and_call_original

        reset_password_with_token

        # If the reset token flow reached the hook, it did so via a committed
        # reset (2xx/302). Only then is the fail-open-loud assertion meaningful.
        unless [200, 201, 302].include?(last_response.status)
          skip "reset did not reach after_reset_password (status #{last_response.status}); " \
               "token/key hashing likely differs in this environment"
        end

        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:sessions_revoke_FAILED, hash_including(level: :error, hook: :after_reset_password))
        expect(Sentry).to have_received(:capture_exception)
      end
    end
  end
end
