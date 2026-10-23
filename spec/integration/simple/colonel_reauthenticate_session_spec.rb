# spec/integration/simple/colonel_reauthenticate_session_spec.rb
#
# frozen_string_literal: true

# Password recovery for a lapsed admin session window (#4331), end to end in
# simple auth mode: POST /api/colonel/reauthenticate is admitted past the idle
# bound, a wrong password leaves the window lapsed, and the right one restores
# it under a new session id.
#
# What only this layer proves: the commit's TrackMetadata write. The exempt
# request arrives on an expired session, so a wrong password must not advance
# last_activity_at on its way out; otherwise one failed POST would reopen the
# whole surface. The decision table is
# spec/unit/onetime/application/auth_strategies/admin_session_lifetime_spec.rb
# and the handler is apps/api/colonel/spec/logic/colonel/reauthenticate_session_spec.rb.

require_relative '../integration_spec_helper'
require_relative '../../support/customer_session_failure_matrix'

RSpec.describe 'Simple-mode colonel password re-authentication (#4331)', type: :integration do
  include_context 'auth_rack_test'
  include CustomerSessionFailureMatrix

  let(:password) { 'Reauth-Simple1234!' }
  let(:db) { Familia.dbclient }
  let(:app) do
    @simple_reauth_app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  let(:colonel) do
    customer = Onetime::Customer.new(email: "reauth-simple-#{SecureRandom.hex(8)}@example.com")
    customer.update_passphrase(password)
    customer.role     = 'colonel'
    customer.verified = 'true'
    customer.save
    customer
  end

  before(:all) do
    Onetime.boot! :test
  end

  before do
    skip 'requires simple auth mode' unless Onetime.auth_config.simple_enabled?

    @saved_conf = YAML.load(YAML.dump(OT.conf))
    clear_cookies
  end

  after { OT.send(:conf=, @saved_conf) if @saved_conf }

  # spec/config.test.yaml disables the bounds suite-wide; enable the idle one.
  def enable_idle_bound
    conf = YAML.load(YAML.dump(OT.conf))
    ((conf['site'] ||= {})['admin'] ||= {})['session'] =
      { 'enabled' => true, 'idle_timeout' => 3_600, 'absolute_timeout' => 0 }
    OT.send(:conf=, conf)
  end

  def sign_in!
    post_json '/auth/login', { login: colonel.email, password: password }
    expect(last_response.status).to eq(200), last_response.body
  end

  def last_activity_at(sid = current_session_id)
    Onetime::SessionMetadata.load(sid)&.last_activity_at.to_i
  end

  def backdate_activity(seconds_ago)
    record = Onetime::SessionMetadata.load(current_session_id)
    raise "no sidecar for the session; TrackMetadata did not run" if record.nil?

    record.last_activity_at = Familia.now.to_i - seconds_ago
    record.save
  end

  def colonel_info_status
    get '/api/colonel/info', {}, { 'HTTP_ACCEPT' => 'application/json' }
    last_response.status
  end

  # post_json fetches its CSRF token with a GET, and that GET is activity: it
  # would undo the backdate. The token is fetched first and reused here.
  def reauthenticate(token, with_password)
    post '/api/colonel/reauthenticate',
      { password: with_password, shrimp: token }.to_json,
      { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json', 'HTTP_X_CSRF_TOKEN' => token }
    last_response
  end

  it 'leaves the window lapsed on a wrong password and restores it on the right one', :aggregate_failures do
    sign_in!
    enable_idle_bound
    token = fetch_csrf_token
    backdate_activity(3_601)
    stale_activity = last_activity_at
    old_sid        = current_session_id

    expect(colonel_info_status).to eq(401)

    wrong = reauthenticate(token, 'not-the-password')
    expect(wrong.status).to eq(403), wrong.body
    expect(JSON.parse(wrong.body)).to include(
      'error' => 'Password verification failed.', 'error_code' => 'reauthentication_failed',
    )
    expect(current_session_id).to eq(old_sid)
    expect(last_activity_at).to eq(stale_activity)
    expect(colonel_info_status).to eq(401)

    right = reauthenticate(token, password)
    expect(right.status).to eq(200), right.body
    body = JSON.parse(right.body)
    expect(body.dig('record', 'reauthenticated')).to be(true)
    expect(body.dig('details', 'session_rotated')).to be(true)

    new_sid = current_session_id
    expect(new_sid).not_to eq(old_sid)
    expect(session_store.find_key(db, old_sid)).to be_nil
    expect(last_activity_at(new_sid)).to be_within(5).of(Familia.now.to_i)
    expect(colonel_info_status).to eq(200)
  end
end
