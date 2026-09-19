# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/mfa_flow_helper'

RSpec.describe 'Auth router MFA-pending session gate', :full_auth_mode, type: :integration do
  include MfaFlowHelper

  let(:email) { "mfa-pending-router-#{SecureRandom.hex(6)}@example.com" }
  let(:account_id) { seed_account_with_password(email) }

  before do
    account_id
    @secret, = provision_totp(email)
    allow_immediate_otp_reuse!(account_id)

    csrf_json_post('/auth/login', login: email, password: AuthTestConstants::TEST_PASSWORD)
    expect(last_response.status).to eq(200), last_response.body
    expect(json_body['mfa_required']).to be(true)
  end

  it 'refuses account reads and session mutations without leaking metadata, then completes MFA' do
    clear_body_headers
    get '/auth/account', {}, 'HTTP_ACCEPT' => 'application/json'

    expect_mfa_pending_refusal
    expect(last_request.env.fetch(Onetime::CustomerSessionEvaluator::ENV_KEY).reason).to eq(:awaiting_mfa)

    expect_any_instance_of(Auth::Config).not_to receive(:remove_all_active_sessions_except_current)
    csrf_json_post('/auth/remove-all-active-sessions', {})

    expect_mfa_pending_refusal
    expect(last_request.env.fetch(Onetime::CustomerSessionEvaluator::ENV_KEY).reason).to eq(:awaiting_mfa)

    csrf_json_post('/auth/otp-auth', otp_code: ROTP::TOTP.new(@secret).now)
    expect(last_response.status).to eq(200), last_response.body

    clear_body_headers
    get '/auth/account', {}, 'HTTP_ACCEPT' => 'application/json'
    expect(last_response.status).to eq(200), last_response.body
    expect(json_body).to include('id' => account_id, 'email' => email)
  end

  it 'refuses anonymous account-lifecycle routes so the MFA challenge cannot be side-stepped' do
    csrf_json_post('/auth/reset-password-request', login: email)
    expect_mfa_pending_refusal

    csrf_json_post('/auth/create-account', login: "another-#{email}", password: AuthTestConstants::TEST_PASSWORD)
    expect_mfa_pending_refusal

    # The challenge remains completable — a refused probe did not strand the session.
    csrf_json_post('/auth/otp-auth', otp_code: ROTP::TOTP.new(@secret).now)
    expect(last_response.status).to eq(200), last_response.body
  end

  it 'serves the challenge page its factor status while account reads stay refused' do
    clear_body_headers
    get '/auth/mfa-status', {}, 'HTTP_ACCEPT' => 'application/json'

    expect(last_response.status).to eq(200), last_response.body
    expect(json_body).to include(
      'enabled' => true,
      'otp_enabled' => true,
      'webauthn_enabled' => false,
    )
    expect(json_body).to have_key('recovery_codes_remaining')
    expect(last_response.body).not_to include(email)

    # The allowance is method-scoped and exact: the same path by another
    # method, and the account reads, are still refused.
    csrf_json_post('/auth/mfa-status', {})
    expect_mfa_pending_refusal

    clear_body_headers
    get '/auth/account', {}, 'HTTP_ACCEPT' => 'application/json'
    expect_mfa_pending_refusal

    get '/auth/account.json', {}, 'HTTP_ACCEPT' => 'application/json'
    expect_mfa_pending_refusal
  end

  it 'refuses to complete MFA on a session whose active-session row was revoked mid-challenge' do
    sid = current_sid
    expect(active_session_rows.count).to be >= 1
    active_session_rows.delete

    csrf_json_post('/auth/otp-auth', otp_code: ROTP::TOTP.new(@secret).now)

    expect_session_expired_refusal
    expect(session_key_for(sid)).to be_nil
    expect(active_session_rows.count).to eq(0), 'a refused completion must not mint a new active-session row'

    # Nothing was promoted: the browser is signed out, not authenticated.
    clear_body_headers
    get '/auth/account', {}, 'HTTP_ACCEPT' => 'application/json'
    expect(last_response.status).to eq(401)
    expect(last_response.body).not_to include(email)
  end

  it 'answers the factor-status read of a revoked MFA-pending session with the session-expired refusal' do
    sid = current_sid
    active_session_rows.delete

    clear_body_headers
    get '/auth/mfa-status', {}, 'HTTP_ACCEPT' => 'application/json'

    expect_session_expired_refusal
    expect(session_key_for(sid)).to be_nil
  end

  it 'refuses to complete MFA on a session presented on another surface' do
    sid = current_sid
    rewrite_session_blob(sid) do |blob|
      blob[Onetime::SessionSurface::KEY] = { 'kind' => 'custom', 'id' => 'other-domain' }
    end

    csrf_json_post('/auth/otp-auth', otp_code: ROTP::TOTP.new(@secret).now)

    expect_session_expired_refusal
    expect(session_key_for(sid)).to be_nil

    clear_body_headers
    get '/auth/account', {}, 'HTTP_ACCEPT' => 'application/json'
    expect(last_response.status).to eq(401)
    expect(last_response.body).not_to include(email)
  end

  def expect_session_expired_refusal
    expect(last_response.status).to eq(401), last_response.body
    expect(json_body).to include(
      'error' => 'web.auth.security.session_expired',
      'success' => false,
    )
    expect(last_response.body).not_to include(email)
  end

  def active_session_rows
    auth_db[:account_active_session_keys].where(account_id: account_id)
  end

  def current_sid
    rack_mock_session.cookie_jar['onetime.session']
  end

  def session_key_for(sid)
    Onetime::Operations::Sessions::Store.find_key(Familia.dbclient, sid)
  end

  def rewrite_session_blob(sid)
    db    = Familia.dbclient
    codec = Onetime::SessionCodec.from_config
    key   = session_key_for(sid)
    data  = Onetime::Operations::Sessions::Store.load_data(db, key, codec: codec)
    yield data
    db.set(key, codec.encode(data), keepttl: true)
  end

  def expect_mfa_pending_refusal
    expect(last_response.status).to eq(401)
    expect(json_body).to eq(
      'error' => 'Authentication required',
      'code' => 'awaiting_mfa',
      'code_scope' => 'customer_session',
    )
    expect(last_response.body).not_to include(email)
    expect(last_response.body).not_to include(account_id.to_s)
  end
end
