# apps/web/auth/spec/integration/full_mfa/verify_account_resend_enumeration_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — direct verify-account-resend enumeration safety
#            (RISK-2026-08-14-M03; full mode + AUTH_VERIFY_ACCOUNT_ENABLED=true)
# =============================================================================
#
# Stock Rodauth answers POST /auth/verify-account-resend with 200 "email sent"
# only for an unverified account with a verification key; an unknown login, a
# verified account, a recently-emailed account and an unverified account with
# no key row each get an error status and body (CWE-204). The SPA uses the
# uniform /api/account/resend-verification-email endpoint, but the Rodauth
# route is mounted at /auth and reachable directly. config/overrides/
# login_request_enumeration.rb answers every state with the route's own
# success response, mailing only the real resend.
#
# These tests assert the same status and JSON body as an unknown login for
# every account state, and that only the real resend mails.
# Sibling: email_login_request_enumeration_spec.rb.
#
# FEATURE GATE: verify_account is one-shot per process and on only in the
# full-mfa lane (tests/lanes/full-mfa/env, AUTH_VERIFY_ACCOUNT_ENABLED=true).
# Elsewhere the route is not mounted and the examples skip, as
# integration/full/resend_verify_account_internal_request_spec.rb does.
#
# RUN:
#   tests/lanes/run full-mfa \
#     --only apps/web/auth/spec/integration/full_mfa/verify_account_resend_enumeration_spec.rb
# =============================================================================

require_relative '../../spec_helper'

RSpec.describe 'Verify-account-resend enumeration safety (RISK-2026-08-14-M03)',
  :aggregate_failures,
  :full_auth_mode,
  type: :integration do
  before do
    unless Auth::Config.features.include?(:verify_account)
      skip 'verify_account feature disabled at boot (AUTH_VERIFY_ACCOUNT_ENABLED); ' \
           'the verify-account-resend route is only mounted when it is enabled'
    end

    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw).and_return(true)
    allow(Auth::Logging).to receive(:log_auth_event).and_call_original
  end

  # An accounts row (plus its Customer) in the given Rodauth status.
  def seed_account(email, status_id:)
    normalized = OT::Utils.normalize_email(email)
    customer   = Onetime::Customer.new(email: normalized)
    customer.save
    auth_db[:accounts].insert(email: normalized, status_id: status_id, external_id: customer.extid)
  end

  # A verification key row. email_last_sent decides whether Rodauth's resend
  # window (verify_account_skip_resend_email_within, 300s by default) is open.
  def seed_verification_key(account_id, email_last_sent:)
    auth_db[:account_verification_keys].insert(
      id: account_id,
      key: SecureRandom.hex(16),
      requested_at: email_last_sent,
      email_last_sent: email_last_sent,
    )
  end

  def probe(login)
    clear_cookies
    csrf_json_post('/auth/verify-account-resend', login: login)
    [last_response.status, json_body]
  end

  def expect_not_mailed
    expect(Onetime::Jobs::Publisher).not_to have_received(:enqueue_email_raw)
  end

  describe 'unknown login' do
    it 'answers with the success response, not a no_matching_login error' do
      status, body = probe(unique_test_email('nobody'))

      expect(status).to eq(200)
      expect(body).not_to have_key('field-error')
      expect(body['error']).to be_nil
      expect(body['success']).to be_a(String)
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:verify_account_resend_no_account, hash_including(level: :info))
      expect_not_mailed
    end
  end

  describe 'unverified account with a key (the real resend)' do
    it 'answers exactly like an unknown login, and mails once' do
      email      = unique_test_email('unverified')
      account_id = seed_account(email, status_id: AuthTestConstants::STATUS_UNVERIFIED)
      seed_verification_key(account_id, email_last_sent: Time.now - 3600)

      resent  = probe(email)
      missing = probe(unique_test_email('missing-resend'))

      expect(resent.first).to eq(200)
      expect(resent).to eq(missing)
      expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email_raw)
        .with(hash_including(to: contain_exactly(email)), any_args).once
    end
  end

  describe 'verified account' do
    it 'answers exactly like an unknown login and mails nothing' do
      email = unique_test_email('verified')
      seed_account(email, status_id: AuthTestConstants::STATUS_VERIFIED)

      verified = probe(email)
      missing  = probe(unique_test_email('missing-verified'))

      expect(verified).to eq(missing)
      expect(verified.last).not_to have_key('field-error')
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:verify_account_resend_ineligible_account, hash_including(level: :info))
      expect_not_mailed
    end
  end

  describe 'closed account' do
    it 'answers exactly like an unknown login and mails nothing' do
      email = unique_test_email('closed')
      seed_account(email, status_id: AuthTestConstants::STATUS_CLOSED)

      expect(probe(email)).to eq(probe(unique_test_email('missing-closed')))
      expect_not_mailed
    end
  end

  describe 'recently-sent throttle' do
    it 'answers exactly like an unknown login without resending (throttle preserved)' do
      email      = unique_test_email('recent')
      account_id = seed_account(email, status_id: AuthTestConstants::STATUS_UNVERIFIED)
      seed_verification_key(account_id, email_last_sent: Time.now)

      throttled = probe(email)
      missing   = probe(unique_test_email('missing-recent'))

      expect(throttled).to eq(missing)
      expect(throttled.last).not_to have_key('error')
      expect_not_mailed
    end
  end

  describe 'unverified account without a key row' do
    it 'answers exactly like an unknown login and mails nothing' do
      email = unique_test_email('no-key')
      seed_account(email, status_id: AuthTestConstants::STATUS_UNVERIFIED)

      no_key  = probe(email)
      missing = probe(unique_test_email('missing-no-key'))

      expect(no_key).to eq(missing)
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:verify_account_resend_no_key, hash_including(level: :info))
      expect_not_mailed
    end
  end

  describe 'internal request (AccountAPI ResendVerifyAccount)' do
    # The override is scoped to the HTTP route: the internal request the
    # uniform /api endpoint makes must still raise for a no-op, which that
    # endpoint logs as :verify_account_resend_blocked.
    it 'still raises for an unknown login' do
      expect { Auth::Config.verify_account_resend(login: unique_test_email('internal')) }
        .to raise_error(Rodauth::InternalRequestError)
    end
  end
end
