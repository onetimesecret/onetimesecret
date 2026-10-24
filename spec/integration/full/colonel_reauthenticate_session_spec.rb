# spec/integration/full/colonel_reauthenticate_session_spec.rb
#
# frozen_string_literal: true

# Password recovery for a lapsed admin session window (#4331), end to end in
# full auth mode after a real Rodauth password login.
#
# The simple-mode sibling (spec/integration/simple/colonel_reauthenticate_session_spec.rb)
# drives the same route against the Redis passphrase. What only this file
# proves: the password is checked through the Rodauth internal request
# (Auth::Config.valid_login_and_password?), and the renewed session id still
# satisfies the full-mode checks the exemption leaves in place, the
# active-session row among them (Onetime::ActiveSessionGate).
#
# Shape of the scenario: the idle bound has lapsed, so a colonel GET answers
# 401; a wrong password answers 403, leaves last_activity_at and the session
# id where they were, and the colonel GET still answers 401; the right
# password answers 200 under a new session id and the colonel GET answers 200.

require 'spec_helper'
require_relative '../../support/customer_session_failure_matrix'

RSpec.describe 'Full-mode colonel password re-authentication (#4331)', type: :integration do
  include_context 'auth_rack_test'
  include CustomerSessionFailureMatrix

  let(:password) { 'Reauth-Full1234!' }
  let(:db) { Familia.dbclient }

  before do
    @saved_conf = YAML.load(YAML.dump(OT.conf))
    allow(Onetime::ColonelAuditEvent).to receive(:record).and_call_original
    allow(Onetime::ColonelAuditEvent).to receive(:record_security).and_call_original
  end

  after { OT.send(:conf=, @saved_conf) if @saved_conf }

  # spec/config.test.yaml disables the bounds suite-wide; enable the idle one.
  def enable_idle_bound
    conf = YAML.load(YAML.dump(OT.conf))
    ((conf['site'] ||= {})['admin'] ||= {})['session'] =
      { 'enabled' => true, 'idle_timeout' => 3_600, 'absolute_timeout' => 0 }
    OT.send(:conf=, conf)
  end

  # A Rodauth password login, then the signed-in Customer is made a verified
  # colonel (the role gate on /api/colonel reads the Customer, not the
  # session).
  def sign_in_colonel!
    email = "reauth-full-#{SecureRandom.hex(8)}@example.com"
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

  def last_activity_at(sid = current_session_id)
    Onetime::SessionMetadata.load(sid)&.last_activity_at.to_i
  end

  def backdate_activity(seconds_ago)
    record = Onetime::SessionMetadata.load(current_session_id)
    raise 'no sidecar for the session; TrackMetadata did not run' if record.nil?

    record.last_activity_at = Familia.now.to_i - seconds_ago
    record.save
  end

  def blob_for(sid)
    key = session_store.find_key(db, sid)
    key && session_store.load_data(db, key, codec: session_codec)
  end

  def colonel_info_status
    get '/api/colonel/info', {}, { 'HTTP_ACCEPT' => 'application/json' }
    last_response.status
  end

  # GET /api/colonel/info for the given cookie, on a fresh cookie jar so the
  # current one is untouched.
  def colonel_info_status_for(sid)
    other = Rack::Test::Session.new(Rack::MockSession.new(app))
    other.set_cookie "onetime.session=#{sid}"
    other.get '/api/colonel/info', {}, { 'HTTP_ACCEPT' => 'application/json' }
    other.last_response.status
  end

  # post_json fetches its CSRF token with a GET, and that GET is activity: it
  # would undo the backdate. The token is fetched first and reused here.
  def reauthenticate(token, with_password)
    post '/api/colonel/reauthenticate',
      { password: with_password, shrimp: token }.to_json,
      { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json', 'HTTP_X_CSRF_TOKEN' => token }
    last_response
  end

  # Signed in, idle window lapsed, CSRF token in hand.
  def lapse_window!
    colonel = sign_in_colonel!
    enable_idle_bound
    token = fetch_csrf_token
    backdate_activity(3_601)
    [colonel, token]
  end

  it 'refuses a wrong password without reopening the window', :aggregate_failures do
    colonel, token = lapse_window!
    stale_activity = last_activity_at
    old_sid        = current_session_id
    signed_in_at   = session_blob['authenticated_at']

    expect(colonel_info_status).to eq(401)

    wrong = reauthenticate(token, 'not-the-password')
    expect(wrong.status).to eq(403), wrong.body
    expect(JSON.parse(wrong.body)).to include('error_code' => 'reauthentication_failed')

    expect(current_session_id).to eq(old_sid)
    expect(last_activity_at).to eq(stale_activity)
    expect(session_blob['authenticated_at']).to eq(signed_in_at)
    expect(colonel_info_status).to eq(401)
    expect(Onetime::ColonelAuditEvent).to have_received(:record_security)
      .with(hash_including(verb: 'colonel.reauthenticate', actor: colonel.extid, result: :failure)).once
    expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      .with(hash_including(verb: 'colonel.reauthenticate'))
  end

  it 'restores the window under a new session id on the right password', :aggregate_failures do
    colonel, token = lapse_window!
    old_sid = current_session_id

    expect(colonel_info_status).to eq(401)

    right = reauthenticate(token, password)
    expect(right.status).to eq(200), right.body
    expect(JSON.parse(right.body).dig('details', 'session_rotated')).to be(true)

    new_sid = current_session_id
    expect(new_sid).not_to eq(old_sid)
    expect(session_store.find_key(db, old_sid)).to be_nil
    expect(Onetime::SessionEnded.ended?(old_sid)).to be(true)

    blob = blob_for(new_sid)
    expect(blob).to include('authenticated' => true, 'external_id' => colonel.extid)
    expect(blob['authenticated_at'].to_i).to be_within(5).of(Familia.now.to_i)
    expect(Onetime::ActiveSessionGate.verdict(blob)).to eq(:active)
    expect(last_activity_at(new_sid)).to be_within(5).of(Familia.now.to_i)

    expect(colonel_info_status).to eq(200)
    expect(colonel_info_status_for(old_sid)).to eq(401)
    expect(Onetime::ColonelAuditEvent).to have_received(:record)
      .with(hash_including(verb: 'colonel.reauthenticate', actor: colonel.extid, result: :success)).once
  end

  it 'recovers on the right password after a wrong one', :aggregate_failures do
    _colonel, token = lapse_window!

    expect(reauthenticate(token, 'not-the-password').status).to eq(403)
    expect(colonel_info_status).to eq(401)

    expect(reauthenticate(token, password).status).to eq(200), last_response.body
    expect(colonel_info_status).to eq(200)
  end
end
