# apps/web/auth/spec/integration/full_mfa/reauth_session_rotation_spec.rb
#
# frozen_string_literal: true

# Session-id renewal at re-authentication (#4466, RISK-2026-09-19-02).
# POST /auth/reauth records a single-use Onetime::RecentReauth proof, which
# lets the session make one Connect attempt. Auth::Operations::Reauthenticate
# renews the id before it records the proof: the old id is ended the way a
# logout ends it and the session data is written back under a new id, so a
# copy of the pre-ceremony id is signed out rather than handed the proof.
#
# Asserted here, against the real /auth routes and the real Onetime::Session
# store:
#   - the id before and after the ceremony differ, and the proof is under
#     the new id only;
#   - the old id's blob is gone and its marker is set;
#   - the account data, the surface marker, the CSRF token and the
#     active-session join key survive;
#   - a request that presents the old id is refused;
#   - a ceremony that stops at the second-factor prompt keeps the id;
#   - when the old id cannot be ended, no proof is recorded and the session
#     stays signed in under the id it had.
#
# LANE: full-mfa (tests/lanes/run full-mfa).

require_relative '../../spec_helper'
require_relative '../../support/mfa_flow_helper'

RSpec.describe 'Session-id renewal at re-authentication (#4466)', :full_auth_mode, type: :integration do
  include MfaFlowHelper

  let(:email) { "reauth-rotation-#{SecureRandom.hex(6)}@example.com" }
  let(:account_id) { seed_account_with_password(email) }
  let(:proof_key) { Onetime::RecentReauth::KEY }

  before { account_id }

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
    env                = { 'HTTP_ACCEPT' => 'application/json' }
    env['HTTP_COOKIE'] = cookie_header if cookie_header
    get '/auth/account', {}, env
    last_response
  end

  # A password sign-in with no second factor. Its after_login records a proof
  # of its own; it is removed so the one under test is the ceremony's.
  def sign_in
    csrf_json_post('/auth/login', login: email, password: AuthTestConstants::TEST_PASSWORD)
    expect(last_response.status).to eq(200), last_response.body
    expect(json_body['mfa_required']).to be_nil
    Onetime::SessionSidecar.delete(current_sid, proof_key)
  end

  def reauth(params = {})
    csrf_json_post('/auth/reauth', { method: 'password', password: AuthTestConstants::TEST_PASSWORD }.merge(params))
  end

  it 'records the proof under a new id and ends the old one', :aggregate_failures do
    sign_in
    old_sid  = current_sid
    old_blob = blob_for(old_sid)
    expect(old_blob).to include('account_id' => account_id, 'authenticated' => true)

    reauth
    expect(last_response.status).to eq(200), last_response.body
    expect(json_body).to eq('success' => 'Re-authentication complete')

    new_sid = current_sid
    expect(new_sid).to match(Onetime::SessionSidecar::SID_FORMAT)
    expect(new_sid).not_to eq(old_sid)

    # The proof is under the new id, and only there.
    expect(Onetime::SessionSidecar.read(new_sid, proof_key)).to include(
      'account_id' => account_id,
      'methods' => %w[password],
    )
    expect(Onetime::SessionSidecar.exists?(old_sid, proof_key)).to be(false)

    # The old id is ended.
    expect(blob_key(old_sid)).to be_nil
    expect(Onetime::SessionEnded.ended?(old_sid)).to be(true)

    # The session data crossed.
    expect(blob_for(new_sid)).to include(
      'account_id' => account_id,
      'authenticated' => true,
      'email' => email,
      'active_session_id_hmac' => old_blob.fetch('active_session_id_hmac'),
      'csrf' => old_blob.fetch('csrf'),
      Onetime::SessionSurface::KEY => old_blob.fetch(Onetime::SessionSurface::KEY),
    )

    # The new id is signed in; the old one is refused and exposes nothing.
    expect(account_read.status).to eq(200), last_response.body
    clear_cookies
    expect(account_read("onetime.session=#{old_sid}").status).to eq(401), last_response.body
    expect(last_response.body).not_to include(email)
  end

  # The surface is checked before the id moves, so the only refusal that can
  # follow the rotation is the proof's sidecar write failing. The id has
  # moved by then; the response says so.
  it 'signals the completed rotation when the proof write fails', :aggregate_failures do
    sign_in
    old_sid = current_sid
    allow(Onetime::SessionSidecar).to receive(:write).and_call_original
    allow(Onetime::SessionSidecar).to receive(:write).with(anything, proof_key, anything).and_return(nil)

    reauth
    expect(last_response.status).to eq(503), last_response.body
    expect(json_body['error_code']).to eq('reauth_not_recorded')
    new_sid = current_sid
    expect(new_sid).not_to eq(old_sid)
    expect(Onetime::SessionEnded.ended?(old_sid)).to be(true)
    expect(blob_key(old_sid)).to be_nil
    expect(Onetime::SessionSidecar.exists?(old_sid, proof_key)).to be(false)
    expect(Onetime::SessionSidecar.exists?(new_sid, proof_key)).to be(false)
    expect(json_body['session_rotated']).to be(true)
    expect(account_read.status).to eq(200), last_response.body
    clear_cookies
    expect(account_read("onetime.session=#{old_sid}").status).to eq(401), last_response.body
  end

  it 'keeps the id while the ceremony waits for a second factor', :aggregate_failures do
    secret,       = provision_totp(email)
    allow_immediate_otp_reuse!(account_id)
    csrf_json_post('/auth/login', login: email, password: AuthTestConstants::TEST_PASSWORD)
    expect(json_body['mfa_required']).to be(true)
    csrf_json_post('/auth/otp-auth', otp_code: ROTP::TOTP.new(secret).now)
    expect(last_response.status).to eq(200), last_response.body
    Onetime::SessionSidecar.delete(current_sid, proof_key)
    signed_in_sid = current_sid

    reauth
    expect(last_response.status).to eq(200), last_response.body
    expect(json_body).to include('mfa_required' => true)
    expect(current_sid).to eq(signed_in_sid)
    expect(Onetime::SessionSidecar.exists?(signed_in_sid, proof_key)).to be(false)

    allow_immediate_otp_reuse!(account_id)
    reauth(otp_code: ROTP::TOTP.new(secret).now)
    expect(last_response.status).to eq(200), last_response.body
    expect(current_sid).not_to eq(signed_in_sid)
    expect(Onetime::SessionSidecar.read(current_sid, proof_key)).to include('methods' => %w[password totp])
  end

  it 'records no proof and keeps the session when the old id cannot be ended', :aggregate_failures do
    sign_in
    old_sid = current_sid

    allow(Onetime::SessionEnded).to receive(:mark).and_return(false)
    reauth
    expect(last_response.status).to eq(503), last_response.body
    expect(json_body['error_code']).to eq('session_not_rotated')
    expect(json_body).not_to have_key('session_rotated')
    allow(Onetime::SessionEnded).to receive(:mark).and_call_original

    # Nothing was touched: same id, still signed in, no proof.
    expect(current_sid).to eq(old_sid)
    expect(Onetime::SessionEnded.ended?(old_sid)).to be(false)
    expect(Onetime::SessionSidecar.exists?(old_sid, proof_key)).to be(false)
    expect(account_read.status).to eq(200), last_response.body
  end
end
