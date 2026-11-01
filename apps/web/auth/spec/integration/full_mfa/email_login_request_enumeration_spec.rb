# apps/web/auth/spec/integration/full_mfa/email_login_request_enumeration_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — email-login-request enumeration safety
#            (RISK-2026-08-14-M03; full mode + AUTH_EMAIL_AUTH_ENABLED=true)
# =============================================================================
#
# Stock Rodauth answers POST /auth/email-login-request with 200 "Login link
# sent" only for an open account; an unknown login, an unverified account and
# a recently-emailed account each get an error status and body, so comparing
# responses enumerates accounts (CWE-204). config/overrides/
# login_request_enumeration.rb answers all of them with the route's own
# success response, sending mail only for the open, non-throttled account.
#
# These tests assert, for every account state, the same status and the same
# JSON body as an unknown login — and that only the real success mails.
# Sibling: integration/full/reset_password_request_enumeration_spec.rb.
#
# WHY THIS LANE: email_auth is one-shot per process (Auth::Config configures
# once) and only the full-mfa lane boots with AUTH_EMAIL_AUTH_ENABLED=true
# (tests/lanes/full-mfa/env). The :full_auth_mode tag is explicit because the
# path-derived tag only matches /integration/full/.
#
# RUN:
#   tests/lanes/run full-mfa \
#     --only apps/web/auth/spec/integration/full_mfa/email_login_request_enumeration_spec.rb
# =============================================================================

# Load-time, before the suite's first boot (see magic_link_session_rotation_spec.rb).
ENV['AUTH_EMAIL_AUTH_ENABLED'] = 'true'

require_relative '../../spec_helper'

RSpec.describe 'Email-login-request enumeration safety (RISK-2026-08-14-M03)',
  :aggregate_failures,
  :full_auth_mode,
  type: :integration do
  # Hard-fail (not skip): this file exists to cover the email_auth route.
  before(:all) do
    next if Auth::Config.method_defined?(:email_auth_route)

    raise 'Rodauth email_auth feature not loaded — this suite must boot with ' \
          'AUTH_EMAIL_AUTH_ENABLED=true in a fresh process (run via ' \
          '`tests/lanes/run full-mfa`; Auth::Config is one-shot)'
  end

  before do
    # The delivery seam (Auth::Config::Email::Delivery hands the rendered mail
    # to the publisher). A spy, so each example can assert who was mailed.
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw).and_return(true)
    allow(Auth::Logging).to receive(:log_auth_event).and_call_original
  end

  # An accounts row (plus its Customer) in the given Rodauth status.
  def seed_account(email, status_id: AuthTestConstants::STATUS_VERIFIED)
    normalized = OT::Utils.normalize_email(email)
    customer   = Onetime::Customer.new(email: normalized)
    customer.save
    auth_db[:accounts].insert(email: normalized, status_id: status_id, external_id: customer.extid)
  end

  # A fresh session per probe, so no cookie state differs between probes.
  def probe(login, **extra)
    clear_cookies
    csrf_json_post('/auth/email-login-request', extra.merge(login: login))
    [last_response.status, json_body]
  end

  # SEC-B01/SEC-B08: a JSON body sent raw, so it can carry a byte that is not
  # valid UTF-8, declared ISO-8859-1 so Rack::UTF8Sanitizer leaves it alone.
  # Auth::ParamEncoding answers it with one 400 before any account lookup.
  def invalid_encoding_probe(path, login, field)
    clear_cookies
    csrf = fetch_csrf_token
    clear_body_headers
    header 'Content-Type', 'application/json; charset=iso-8859-1'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', csrf if csrf
    body = %({"login":#{JSON.generate(login)},"shrimp":#{JSON.generate(csrf.to_s)},"#{field}":"\xFF"})
    post path, body.b
    [last_response.status, last_response.body]
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
        .with(:email_auth_request_no_account, hash_including(level: :info))
      expect_not_mailed
    end
  end

  describe 'open account (the real success)' do
    it 'answers exactly like an unknown login, and mails the link once' do
      email = unique_test_email('open')
      seed_account(email)

      open_status,    open_body    = probe(email)
      missing_status, missing_body = probe(unique_test_email('missing-open'))

      expect(open_status).to eq(200)
      expect([open_status, open_body]).to eq([missing_status, missing_body])
      expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email_raw)
        .with(hash_including(to: contain_exactly(email)), any_args).once
    end
  end

  describe 'unverified account' do
    it 'answers exactly like an unknown login and mails nothing' do
      email = unique_test_email('unverified')
      seed_account(email, status_id: AuthTestConstants::STATUS_UNVERIFIED)

      unverified = probe(email)
      missing    = probe(unique_test_email('missing-unverified'))

      expect(unverified).to eq(missing)
      expect(unverified.last).not_to have_key('field-error')
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:email_auth_request_unopen_account, hash_including(level: :info))
      expect_not_mailed
    end
  end

  describe 'closed account' do
    it 'answers exactly like an unknown login and mails nothing' do
      email = unique_test_email('closed')
      seed_account(email, status_id: AuthTestConstants::STATUS_CLOSED)

      closed = probe(email)

      # Absolute anchor: stock Rodauth answers BOTH probes 401
      # no_matching_login (a closed account is never found), so equality
      # alone would pass with the override removed.
      expect(closed.first).to eq(200)
      expect(closed.last['success']).to be_a(String)
      expect(closed).to eq(probe(unique_test_email('missing-closed')))
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:email_auth_request_no_account, hash_including(level: :info)).twice
      expect_not_mailed
    end
  end

  describe 'recently-sent throttle' do
    it 'answers exactly like an unknown login without resending (throttle preserved)' do
      email      = unique_test_email('recent')
      account_id = seed_account(email)

      # A link that was just mailed: a live key row whose email_last_sent is
      # inside email_auth_skip_resend_email_within (30s, features/email_auth.rb).
      auth_db[:account_email_auth_keys].insert(
        id: account_id,
        key: SecureRandom.hex(16),
        deadline: Time.now + (15 * 60),
        email_last_sent: Time.now,
      )

      throttled = probe(email)
      missing   = probe(unique_test_email('missing-recent'))

      expect(throttled).to eq(missing)
      expect(throttled.first).to eq(200)
      expect(throttled.last).not_to have_key('error')
      expect_not_mailed
    end
  end

  # SEC-B01: the magic-link template translates with the requested locale,
  # and I18n raises I18n::InvalidLocale for one the app has not loaded. Only
  # an open account builds that email, so an unsupported `locale` answered 500
  # for an account and 200 for a missing login. The email helper now falls
  # back to an available locale (config/email/helpers.rb).
  describe 'unsupported locale param' do
    it 'answers an open account and an unknown login identically, still mailing the account' do
      email = unique_test_email('locale-open')
      seed_account(email)

      open    = probe(email, locale: 'zz')
      missing = probe(unique_test_email('locale-missing'), locale: 'zz')

      expect(open.first).to eq(200)
      expect(open).to eq(missing)
      expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email_raw)
        .with(hash_including(to: contain_exactly(email)), any_args).once
    end
  end

  describe 'invalid-encoding param (SEC-B01)' do
    it 'answers an open account and an unknown login with the same 400' do
      email = unique_test_email('encoding-open')
      seed_account(email)

      answer = invalid_encoding_probe('/auth/email-login-request', email, 'locale')

      expect(answer.first).to eq(400)
      expect(answer).to eq(invalid_encoding_probe('/auth/email-login-request', unique_test_email('encoding-missing'), 'locale'))
      expect_not_mailed
    end
  end
end
