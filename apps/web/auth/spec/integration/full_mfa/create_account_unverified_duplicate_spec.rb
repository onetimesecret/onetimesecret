# apps/web/auth/spec/integration/full_mfa/create_account_unverified_duplicate_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration: sign-up for an address that already has an
#            UNVERIFIED account (full mode + AUTH_VERIFY_ACCOUNT_ENABLED=true)
# =============================================================================
#
# POST /auth/create-account answers a login that already has an account with
# the response a fresh sign-up gets (audit 2026-08-02 M-2,
# config/overrides/account_enumeration.rb and the before_create_account
# duplicate branch in config/hooks/account.rb). For an unverified account it
# sends nothing and leaves the verification key alone: a sign-up attempt
# should not mail the verification link of an account whose password the
# requester did not set. The address owner can use Resend
# (POST /auth/verify-account-resend), which still mails.
#
# FEATURE GATE: verify_account is one-shot per process and on only in the
# full-mfa lane (tests/lanes/full-mfa/env, AUTH_VERIFY_ACCOUNT_ENABLED=true).
# Elsewhere a new account is created open, there is no verification email,
# and the examples skip.
#
# RUN:
#   tests/lanes/run full-mfa \
#     --only apps/web/auth/spec/integration/full_mfa/create_account_unverified_duplicate_spec.rb
# =============================================================================

require_relative '../../spec_helper'

RSpec.describe 'Sign-up for an address that has an unverified account',
  :aggregate_failures,
  :full_auth_mode,
  type: :integration do
  let(:password) { 'Unverified-Dup1234!xyz' }

  # Every email a request sends, verification or otherwise.
  let(:mailed) { [] }

  before do
    unless Auth::Config.features.include?(:verify_account)
      skip 'verify_account feature disabled at boot (AUTH_VERIFY_ACCOUNT_ENABLED); ' \
           'new accounts are created open and get no verification email'
    end

    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw) do |*args, **|
      mailed << args
      true
    end
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email) do |*args, **|
      mailed << args
      true
    end
  end

  # Signup addresses must pass Truemail and SignupValidation, so they use
  # @example.com (as create_account_enumeration_spec.rb does), not
  # unique_test_email's domain.
  def signup_email(prefix)
    "#{prefix}-#{SecureRandom.hex(8)}@example.com"
  end

  # One sign-up from a fresh browser: new session, new CSRF token.
  def sign_up(email)
    clear_cookies
    csrf_json_post('/auth/create-account', login: email, password: password)
    answer(last_response)
  end

  # Everything a caller can compare two answers by. The CSRF token, the
  # request id and the session cookie's value and expiry are per request, so
  # only their presence, and the cookie's name and attributes, are kept.
  def answer(response)
    headers = response.headers.to_h.transform_keys(&:downcase)
    {
      status: response.status,
      body: JSON.parse(response.body),
      headers: headers.except('x-csrf-token', 'x-request-id', 'set-cookie'),
      per_request_headers: headers.slice('x-csrf-token', 'x-request-id').transform_values { |v| !v.to_s.empty? },
      cookies: headers['set-cookie'].to_s.split("\n").map { |cookie| cookie_shape(cookie) },
    }
  end

  def cookie_shape(cookie)
    name, *attributes = cookie.split(/;\s*/)
    [name.split('=', 2).first, *attributes.map { |attribute| attribute.sub(/\Aexpires=.*/i, 'expires') }]
  end

  def account_rows(email)
    auth_db[:accounts].where(email: OT::Utils.normalize_email(email)).all
  end

  def verification_key_row(account_id)
    auth_db[:account_verification_keys].where(id: account_id).first
  end

  # An unverified account made by an ordinary sign-up, its verification email
  # last sent an hour ago: outside Rodauth's resend window
  # (verify_account_skip_resend_email_within, 300 seconds), so that window
  # alone would not hold a resend back. Clears the mail the sign-up sent.
  def unverified_account(email)
    expect(sign_up(email)[:status]).to eq(200)
    account = account_rows(email).first
    expect(account[:status_id]).to eq(AuthTestConstants::STATUS_UNVERIFIED)
    expect(verification_key_row(account[:id])).not_to be_nil

    auth_db[:account_verification_keys].where(id: account[:id]).update(email_last_sent: Time.now - 3600)
    mailed.clear
    account
  end

  it 'sends no email and leaves the account and its verification key as they were' do
    email   = signup_email('dup-unverified')
    account = unverified_account(email)
    key     = verification_key_row(account[:id])

    expect(sign_up(email)[:status]).to eq(200)

    expect(mailed).to be_empty, "a duplicate sign-up sent: #{mailed.inspect}"
    expect(verification_key_row(account[:id])).to eq(key)
    expect(account_rows(email)).to eq([account])
  end

  it 'answers exactly like a fresh sign-up and like a sign-up for a verified account' do
    email = signup_email('dup-unverified')
    unverified_account(email)

    verified = signup_email('dup-verified')
    expect(sign_up(verified)[:status]).to eq(200)
    auth_db[:accounts].where(email: verified).update(status_id: AuthTestConstants::STATUS_VERIFIED)

    duplicate = sign_up(email)

    expect(duplicate[:status]).to eq(200)
    expect(duplicate[:body]).not_to have_key('error')
    expect(duplicate[:body]).not_to have_key('field-error')
    expect(duplicate).to eq(sign_up(signup_email('fresh')))
    expect(duplicate).to eq(sign_up(verified))
  end

  it 'leaves Resend working for that account after the duplicate sign-up' do
    email   = signup_email('dup-resend')
    account = unverified_account(email)
    key     = verification_key_row(account[:id])

    sign_up(email)
    mailed.clear

    clear_cookies
    csrf_json_post('/auth/verify-account-resend', login: email)

    expect(last_response.status).to eq(200)
    expect(mailed.map(&:first)).to contain_exactly(include(to: contain_exactly(email))),
      "expected one resend to #{email}, got: #{mailed.inspect}"
    expect(verification_key_row(account[:id])[:key]).to eq(key[:key])
  end
end
