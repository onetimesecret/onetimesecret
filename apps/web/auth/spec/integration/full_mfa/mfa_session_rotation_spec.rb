# apps/web/auth/spec/integration/full_mfa/mfa_session_rotation_spec.rb
#
# frozen_string_literal: true

# Session-id rotation on second-factor completion (#4466,
# RISK-2026-09-19-02). apps/web/auth/config/hooks/two_factor.rb calls
# Onetime::SessionRotation from after_two_factor_authentication: the
# MFA-pending id is ended the way a logout ends it (SessionEnded marker, blob,
# sidecar keys, metadata record) and the session data is written back under
# a fresh id in the same request.
#
# Asserted here, against the real /auth routes and the real Onetime::Session
# store:
#   - the id before and after the second factor differ;
#   - the pending id's blob is gone, its marker is set, its sidecar keys are
#     purged;
#   - the account data, the surface marker, the CSRF token and the
#     active-session join key survive, and the active-session row is the
#     same row;
#   - sidecar values cross: a merged externalized field written on the
#     pending id is readable under the new id, and the recent-reauth proof
#     the hook records lands under the new id;
#   - a request that presents the pending id is refused and the id is not
#     re-issued.
#
# LANE: full-mfa (tests/lanes/run full-mfa).

require_relative '../../spec_helper'
require_relative '../../support/mfa_flow_helper'

RSpec.describe 'Session-id rotation on second-factor completion (#4466)', :full_auth_mode, type: :integration do
  include MfaFlowHelper

  let(:email) { "mfa-rotation-#{SecureRandom.hex(6)}@example.com" }
  let(:account_id) { seed_account_with_password(email) }

  before do
    account_id
    @secret, = provision_totp(email)
    allow_immediate_otp_reuse!(account_id)
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

  def active_session_rows
    auth_db[:account_active_session_keys].where(account_id: account_id)
  end

  def password_step
    csrf_json_post('/auth/login', login: email, password: AuthTestConstants::TEST_PASSWORD)
    expect(last_response.status).to eq(200), last_response.body
    expect(json_body['mfa_required']).to be(true)
  end

  def otp_step
    csrf_json_post('/auth/otp-auth', otp_code: ROTP::TOTP.new(@secret).now)
    expect(last_response.status).to eq(200), last_response.body
  end

  def account_read(cookie_header = nil)
    clear_body_headers
    env = { 'HTTP_ACCEPT' => 'application/json' }
    env['HTTP_COOKIE'] = cookie_header if cookie_header
    get '/auth/account', {}, env
    last_response
  end

  it 'issues a new id, ends the pending one, and carries the session across', :aggregate_failures do
    password_step

    pending_sid  = current_sid
    pending_blob = blob_for(pending_sid)
    expect(pending_sid).to match(Onetime::SessionSidecar::SID_FORMAT)
    expect(pending_blob).to include('account_id' => account_id)
    expect(pending_blob['authenticated']).not_to be(true)
    expect(Onetime::SessionSidecar.exists?(pending_sid, 'awaiting_mfa')).to be(true)

    join_key = pending_blob.fetch('active_session_id_hmac')
    expect(active_session_rows.where(session_id: join_key).count).to eq(1)

    # A merged, externalized sidecar value on the pending id. It is overlaid
    # into the session hash on the read, so it must cross with the hash and
    # be re-externalized under the new id by the commit.
    expect(Onetime::SessionSidecar.write(pending_sid, 'domain_context', { 'domain' => 'rotation.example' })).to be_truthy

    otp_step
    authenticated_sid = current_sid

    # A different id.
    expect(authenticated_sid).to match(Onetime::SessionSidecar::SID_FORMAT)
    expect(authenticated_sid).not_to eq(pending_sid)

    # The pending id is ended: blob gone, marker set, sidecar keys purged.
    expect(blob_key(pending_sid)).to be_nil
    expect(Onetime::SessionEnded.ended?(pending_sid)).to be(true)
    expect(Onetime::SessionSidecar.exists?(pending_sid, 'awaiting_mfa')).to be(false)
    expect(Onetime::SessionSidecar.exists?(pending_sid, 'domain_context')).to be(false)
    expect(Onetime::SessionMetadata.load(pending_sid)).to be_nil

    # The account data survived, under the new id.
    blob = blob_for(authenticated_sid)
    expect(blob).to include(
      'account_id' => account_id,
      'authenticated' => true,
      'email' => email,
      'active_session_id_hmac' => join_key,
      'csrf' => pending_blob.fetch('csrf'),
      Onetime::SessionSurface::KEY => pending_blob.fetch(Onetime::SessionSurface::KEY),
    )
    expect(blob['external_id']).not_to be_nil
    expect(blob['authenticated_at']).to be_a(Integer)
    expect(blob['awaiting_mfa']).not_to be(true)

    # The active-session row survived, and it is the same row.
    expect(active_session_rows.count).to eq(1)
    expect(active_session_rows.where(session_id: join_key).count).to eq(1)

    # The metadata record is written for the new id (Sessions::TrackMetadata
    # runs on the commit that persists the authenticated session).
    expect(Onetime::SessionMetadata.load(authenticated_sid)).not_to be_nil

    # Sidecar values under the new id: the carried externalized field, the
    # proof the hook recorded after rotating, and no pending flag.
    expect(Onetime::SessionSidecar.read(authenticated_sid, 'domain_context')).to eq('domain' => 'rotation.example')
    expect(Onetime::SessionSidecar.exists?(authenticated_sid, 'awaiting_mfa')).to be(false)
    proof = Onetime::SessionSidecar.read(authenticated_sid, Onetime::RecentReauth::KEY)
    expect(proof).to include('account_id' => account_id)
    expect(Array(proof['methods']).first).to eq('password')

    # ADR-046: the epoch is derived from the id, so the stream restarts.
    expect(Onetime::SnapshotOrdering.epoch_for(authenticated_sid)).not_to eq(Onetime::SnapshotOrdering.epoch_for(pending_sid))

    # The new id is a working authenticated session.
    expect(account_read.status).to eq(200), last_response.body
    expect(json_body).to include('id' => account_id, 'email' => email)

    # The pending id is refused, exposes nothing, and is not re-issued.
    clear_cookies
    expect(account_read("onetime.session=#{pending_sid}").status).to eq(401), last_response.body
    expect(last_response.body).not_to include(email)
    expect(last_response.body).not_to include(account_id.to_s)
    expect(current_sid).not_to eq(pending_sid)
  end

  it 'refuses a request that presents both ids together, in either order', :aggregate_failures do
    password_step
    pending_sid = current_sid
    otp_step
    authenticated_sid = current_sid

    clear_cookies
    expect(account_read("onetime.session=#{pending_sid}; onetime.session=#{authenticated_sid}").status).to eq(403)
    expect(last_response.body).not_to include(email)

    clear_cookies
    expect(account_read("onetime.session=#{authenticated_sid}; onetime.session=#{pending_sid}").status).to eq(403)
    expect(last_response.body).not_to include(email)
  end
end
