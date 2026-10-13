# spec/integration/full/colonel_elevation_session_rotation_spec.rb
#
# frozen_string_literal: true

# Colonel step-up starts a new session id (#4466).
#
# POST /api/colonel/elevation verifies a factor and writes the step-up
# window (ColonelAPI::Logic::Colonel::ElevateSession, #4327). The window
# gives the session id tier-1 (destructive) capability, so the id that
# existed before the step-up is ended and the window is written under a new
# one (Onetime::SessionRotation). These examples drive the route end to end
# in full auth mode, after a real Rodauth password login: the operator is
# still signed in and elevated under the new id, the active-session row
# still matches it, and the old cookie is not signed in.

require 'spec_helper'
require_relative '../../support/customer_session_failure_matrix'

RSpec.describe 'Colonel step-up starts a new session id (#4466)', type: :integration do
  include_context 'auth_rack_test'
  include CustomerSessionFailureMatrix

  let(:password) { 'Elevation-Rotation1234!' }
  let(:db) { Familia.dbclient }

  before do
    stub_colonel_elevation(enabled: true, window: 600)
    allow(Onetime::ColonelAuditEvent).to receive(:record).and_call_original
    allow(Onetime::ColonelAuditEvent).to receive(:record_security).and_call_original
  end

  # A Rodauth password login, then the signed-in Customer is made a verified
  # colonel (the role gate on /api/colonel reads the Customer, not the
  # session).
  def sign_in_colonel!
    email = "elevation-rotation-#{SecureRandom.hex(8)}@example.com"
    create_verified_account(db: test_db, email: email, password: password)

    clear_cookies
    post_json '/auth/login', { login: email, password: password }
    expect(last_response.status).to eq(200), last_response.body

    colonel          = Onetime::Customer.find_by_extid(session_blob.fetch('external_id'))
    colonel.role     = 'colonel'
    colonel.verified = 'true'
    colonel.save
    colonel
  end

  def elevate!(factor: 'password', secret: password)
    post_json '/api/colonel/elevation', { factor: factor, password: secret }
    last_response
  end

  def blob_for(sid)
    key = session_store.find_key(db, sid)
    key && session_store.load_data(db, key, codec: session_codec)
  end

  # GET /api/colonel/elevation for the given cookie, on a fresh cookie jar so
  # the current one is untouched.
  def elevation_status_for(sid)
    other = Rack::Test::Session.new(Rack::MockSession.new(app))
    other.set_cookie "onetime.session=#{sid}"
    other.get '/api/colonel/elevation', {}, { 'HTTP_ACCEPT' => 'application/json' }
    other.last_response
  end

  it 'writes the window under a new id and ends the old one', :aggregate_failures do
    colonel = sign_in_colonel!
    old_sid = current_session_id
    expect(old_sid).not_to be_nil

    expect(elevate!.status).to eq(200), last_response.body
    expect(json_response.dig('record', 'elevated')).to be(true)

    new_sid = current_session_id
    expect(new_sid).not_to be_nil
    expect(new_sid).not_to eq(old_sid)
    expect(session_store.find_key(db, old_sid)).to be_nil
    expect(Onetime::SessionEnded.ended?(old_sid)).to be(true)

    blob = blob_for(new_sid)
    expect(blob).to include('authenticated' => true, 'external_id' => colonel.extid)
    expect(blob['active_session_id_hmac']).not_to be_nil
    expect(Onetime::ActiveSessionGate.verdict(blob)).to eq(:active)
    expect(Onetime::SessionSidecar.read(new_sid, 'elevated_until')).to include('extid' => colonel.extid)
    expect(Onetime::SessionSidecar.read(old_sid, 'elevated_until')).to be_nil
  end

  it 'keeps the operator signed in and elevated under the new id, and the old cookie signed out', :aggregate_failures do
    sign_in_colonel!
    old_sid = current_session_id
    expect(elevate!.status).to eq(200), last_response.body
    new_sid = current_session_id

    current = elevation_status_for(new_sid)
    expect(current.status).to eq(200), current.body
    expect(JSON.parse(current.body).dig('record', 'elevated')).to be(true)

    expect(elevation_status_for(old_sid).status).to eq(401)
  end

  it 'accepts the CSRF token the operator already held on the next request' do
    sign_in_colonel!
    token = fetch_csrf_token
    expect(elevate!.status).to eq(200), last_response.body

    delete '/api/colonel/elevation', {}, { 'HTTP_ACCEPT' => 'application/json', 'HTTP_X_CSRF_TOKEN' => token }
    expect(last_response.status).to eq(200), last_response.body
  end

  it 'records one success event for the step-up' do
    colonel = sign_in_colonel!
    expect(elevate!.status).to eq(200), last_response.body

    expect(Onetime::ColonelAuditEvent).to have_received(:record)
      .with(hash_including(verb: 'colonel.elevate', actor: colonel.extid, result: :success)).once
  end

  # The window is not granted on a session id that could not be ended. The
  # operator stays signed in, unelevated.
  describe 'when the old id cannot be ended' do
    it 'refuses the window and records no success event', :aggregate_failures do
      colonel = sign_in_colonel!
      old_sid = current_session_id
      allow(Onetime::SessionEnded).to receive(:mark).and_return(false)

      response = elevate!
      expect(response.status).to eq(403)
      expect(json_response).to include('error_code' => 'elevation_failed')

      expect(current_session_id).to eq(old_sid)
      expect(Onetime::SessionSidecar.read(old_sid, 'elevated_until')).to be_nil
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
        .with(hash_including(verb: 'colonel.elevate', result: :success))
      expect(Onetime::ColonelAuditEvent).to have_received(:record_security)
        .with(hash_including(verb: 'colonel.elevate', actor: colonel.extid, result: :failure))

      status = elevation_status_for(old_sid)
      expect(status.status).to eq(200), status.body
      expect(JSON.parse(status.body).dig('record', 'elevated')).to be(false)
    end
  end
end
