# apps/web/auth/spec/integration/full_mfa/factor_setup_session_rotation_spec.rb
#
# frozen_string_literal: true

# Session-id renewal at second-factor setup (#4466, RISK-2026-09-19-02).
# Setting up the first second factor on a session that is not yet two-factor
# authenticated makes it one: Rodauth's otp-setup and webauthn-setup routes
# call two_factor_update_session(type) inside the setup transaction. The
# owning hooks (before_/after_otp_setup in hooks/mfa.rb,
# before_/after_webauthn_setup in hooks/webauthn.rb) call the helpers in
# hooks/two_factor.rb, which renew the id when the setup marked the session.
#
# Asserted here, against the real /auth routes and the real Onetime::Session
# store:
#   - TOTP setup and passkey setup on a password-only session move it to a
#     new id, end the old one, and the new id carries the factor;
#   - a setup on a session that is already two-factor authenticated keeps
#     the id;
#   - when the old id cannot be ended, the setup is refused: no factor and no
#     recovery codes are stored, and the session stays signed in under the
#     id it had, without the factor.
#
# LANE: full-mfa (tests/lanes/run full-mfa).

require_relative '../../spec_helper'
require_relative '../../support/mfa_flow_helper'
require_relative '../../support/webauthn_flow_helper'

RSpec.describe 'Session-id renewal at second-factor setup (#4466)', :full_auth_mode, type: :integration do
  include MfaFlowHelper
  include WebauthnFlowHelper

  # Passkeys are registered for the installed canonical host, as in
  # omniauth_connect_reauth_webauthn_spec.rb.
  include_context 'domains enabled'

  let(:email) { "setup-rotation-#{SecureRandom.hex(6)}@example.com" }
  let(:account_id) { seed_account_with_password(email) }

  before do
    account_id
    header 'Host', canonical_host
  end

  def current_sid
    rack_mock_session.cookie_jar['onetime.session']
  end

  def blob_key(sid)
    Onetime::Operations::Sessions::Store.find_key(Familia.dbclient, sid)
  end

  def blob_for(sid)
    key = blob_key(sid)
    return nil if key.nil?

    Onetime::Operations::Sessions::Store.load_data(Familia.dbclient, key, codec: Onetime::SessionCodec.from_config)
  end

  def account_read(cookie_header = nil)
    clear_body_headers
    header 'Host', canonical_host
    env                = { 'HTTP_ACCEPT' => 'application/json' }
    env['HTTP_COOKIE'] = cookie_header if cookie_header
    get '/auth/account', {}, env
    last_response
  end

  def sign_in_with_password
    csrf_json_post('/auth/login', login: email, password: AuthTestConstants::TEST_PASSWORD)
    expect(last_response.status).to eq(200), last_response.body
    expect(json_body['mfa_required']).to be_nil
  end

  # Phase 1 of the TOTP setup: the secret, in a 422 (mfa_flow_helper.rb).
  def otp_setup_secret
    csrf_json_post('/auth/otp-setup', {})
    expect(last_response.status).to eq(422), last_response.body
    [json_body.fetch('otp_setup'), json_body.fetch('otp_raw_secret')]
  end

  def confirm_otp_setup(secret, raw_secret)
    csrf_json_post(
      '/auth/otp-setup',
      otp_setup: secret,
      otp_raw_secret: raw_secret,
      otp_code: ROTP::TOTP.new(secret).now,
      password: AuthTestConstants::TEST_PASSWORD,
    )
  end

  # Both phases of the passkey setup on the current session
  # (webauthn_flow_helper.rb#register_passkey_as_sent, without its sign-in).
  def register_passkey_on_current_session
    csrf_json_post('/auth/webauthn-setup', password: AuthTestConstants::TEST_PASSWORD)
    expect(last_response.status).to eq(422), last_response.body
    setup     = json_body
    challenge = setup.fetch('webauthn_setup_challenge')
    client    = WebAuthn::FakeClient.new(passkey_origin(canonical_host))
    csrf_json_post(
      '/auth/webauthn-setup',
      webauthn_setup: client.create(challenge: challenge, rp_id: setup.dig('webauthn_setup', 'rp', 'id')),
      webauthn_setup_challenge: challenge,
      webauthn_setup_challenge_hmac: setup.fetch('webauthn_setup_challenge_hmac'),
      password: AuthTestConstants::TEST_PASSWORD,
    )
  end

  def expect_old_id_ended(old_sid)
    expect(blob_key(old_sid)).to be_nil
    expect(Onetime::SessionEnded.ended?(old_sid)).to be(true)
    clear_cookies
    expect(account_read("onetime.session=#{old_sid}").status).to eq(401), last_response.body
    expect(last_response.body).not_to include(email)
  end

  it 'moves the session to a new id when TOTP setup makes it two-factor', :aggregate_failures do
    sign_in_with_password
    secret, raw_secret = otp_setup_secret
    old_sid            = current_sid
    old_blob           = blob_for(old_sid)
    expect(Array(old_blob['authenticated_by'])).to eq(%w[password])

    confirm_otp_setup(secret, raw_secret)
    expect(last_response.status).to eq(200), last_response.body
    new_sid = current_sid
    expect(new_sid).to match(Onetime::SessionSidecar::SID_FORMAT)
    expect(new_sid).not_to eq(old_sid)

    expect(blob_for(new_sid)).to include(
      'account_id' => account_id,
      'authenticated' => true,
      'active_session_id_hmac' => old_blob.fetch('active_session_id_hmac'),
      'csrf' => old_blob.fetch('csrf'),
    )
    expect(Array(blob_for(new_sid)['authenticated_by'])).to eq(%w[password totp])
    expect(account_read.status).to eq(200), last_response.body

    expect_old_id_ended(old_sid)
  end

  it 'moves the session to a new id when passkey setup makes it two-factor', :aggregate_failures do
    sign_in_with_password
    old_sid = current_sid

    register_passkey_on_current_session
    expect(last_response.status).to eq(200), last_response.body
    new_sid = current_sid
    expect(new_sid).not_to eq(old_sid)
    expect(Array(blob_for(new_sid)['authenticated_by'])).to eq(%w[password webauthn])
    expect(auth_db[:account_webauthn_keys].where(account_id: account_id).count).to eq(1)
    expect(account_read.status).to eq(200), last_response.body

    expect_old_id_ended(old_sid)
  end

  it 'keeps the id when the session is already two-factor authenticated', :aggregate_failures do
    secret,       = provision_totp(email)
    header 'Host', canonical_host
    allow_immediate_otp_reuse!(account_id)
    csrf_json_post('/auth/login', login: email, password: AuthTestConstants::TEST_PASSWORD)
    expect(json_body['mfa_required']).to be(true)
    csrf_json_post('/auth/otp-auth', otp_code: ROTP::TOTP.new(secret).now)
    expect(last_response.status).to eq(200), last_response.body
    signed_in_sid = current_sid

    register_passkey_on_current_session
    expect(last_response.status).to eq(200), last_response.body
    expect(current_sid).to eq(signed_in_sid)
    expect(Array(blob_for(signed_in_sid)['authenticated_by'])).to eq(%w[password totp])
  end

  it 'refuses the setup and keeps the session when the old id cannot be ended', :aggregate_failures do
    sign_in_with_password
    secret, raw_secret = otp_setup_secret
    old_sid            = current_sid

    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_call_original
    allow(Onetime::SessionEnded).to receive(:mark).and_return(false)
    confirm_otp_setup(secret, raw_secret)
    expect(last_response.status).to eq(500), last_response.body
    expect(last_response.body).not_to include('recovery_codes')
    allow(Onetime::SessionEnded).to receive(:mark).and_call_original

    # The setup rolled back: no factor, no recovery codes, no "enabled" email.
    expect(Onetime::Jobs::Publisher).not_to have_received(:enqueue_email).with(:mfa_enabled, any_args)
    expect(auth_db[:account_otp_keys].where(id: account_id).count).to eq(0)
    expect(auth_db[:account_recovery_codes].where(id: account_id).count).to eq(0)

    # Same id, still signed in, without the factor.
    expect(current_sid).to eq(old_sid)
    expect(Onetime::SessionEnded.ended?(old_sid)).to be(false)
    expect(Array(blob_for(old_sid)['authenticated_by'])).to eq(%w[password])
    expect(account_read.status).to eq(200), last_response.body
  end
end
