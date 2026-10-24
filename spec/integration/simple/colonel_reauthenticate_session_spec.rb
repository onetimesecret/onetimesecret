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

  # The exemption is matched on the method and SCRIPT_NAME + PATH_INFO as the
  # auth strategy sees them (AdminSessionLifetime#admin_reauth_exempt?), while
  # Otto dispatches on its own normalized path (one trailing slash stripped).
  # These pin the request forms where the two could disagree: each one either
  # reaches the handler AND the exemption, or neither. There is no
  # Rack::MethodOverride in the stack, so `_method` is inert.
  #
  # The ABSOLUTE bound is lapsed here, not the idle one: any request that is
  # not refused (a 404 included) counts as session activity by design (see the
  # AdminSessionLifetime header), which would reopen an idle window and hide
  # whether a form was admitted. Only a verified re-authentication re-stamps
  # authenticated_at, so a colonel GET still answering 401 afterwards proves
  # the form did not get through.
  describe 'which request forms the exemption admits' do
    before do
      sign_in!
      conf = YAML.load(YAML.dump(OT.conf))
      ((conf['site'] ||= {})['admin'] ||= {})['session'] =
        { 'enabled' => true, 'idle_timeout' => 0, 'absolute_timeout' => 60 }
      OT.send(:conf=, conf)
      @token     = fetch_csrf_token
      @signed_at = Familia.now.to_i - 120
      rewrite_session_blob { |data| data['authenticated_at'] = @signed_at }
      @old_sid = current_session_id
      expect(colonel_info_status).to eq(401)
    end

    def reauthenticate_at(path, with_password, extra = {})
      post path,
        { password: with_password, shrimp: @token }.merge(extra).to_json,
        { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json', 'HTTP_X_CSRF_TOKEN' => @token }
      last_response
    end

    def expect_window_still_lapsed
      expect(current_session_id).to eq(@old_sid)
      expect(session_blob['authenticated_at'].to_i).to eq(@signed_at)
      expect(colonel_info_status).to eq(401)
    end

    def expect_reauthenticated(response)
      expect(response.status).to eq(200), response.body
      expect(JSON.parse(response.body).dig('record', 'reauthenticated')).to be(true)
      expect(current_session_id).not_to eq(@old_sid)
      expect(colonel_info_status).to eq(200)
    end

    it 'admits the trailing-slash form, which Otto routes to the handler', :aggregate_failures do
      wrong = reauthenticate_at('/api/colonel/reauthenticate/', 'not-the-password')
      expect(wrong.status).to eq(403), wrong.body
      expect(JSON.parse(wrong.body)).to include('error_code' => 'reauthentication_failed')
      expect_window_still_lapsed

      expect_reauthenticated(reauthenticate_at('/api/colonel/reauthenticate/', password))
    end

    it 'admits a query string (PATH_INFO carries none)' do
      expect_reauthenticated(reauthenticate_at('/api/colonel/reauthenticate?x=1', password))
    end

    # The auth strategy sees the decoded PATH_INFO, the same one Otto
    # dispatches on, so the encoded form is the same request, not a bypass.
    it 'treats a percent-encoded path as the same request' do
      expect_reauthenticated(reauthenticate_at('/api/colonel/%72eauthenticate', password))
    end

    it 'does not admit a doubled slash, and nothing reaches the handler', :aggregate_failures do
      response = reauthenticate_at('/api/colonel//reauthenticate', password)
      expect(response.status).to eq(404), response.body
      expect_window_still_lapsed
    end

    it 'does not admit a second trailing slash', :aggregate_failures do
      response = reauthenticate_at('/api/colonel/reauthenticate//', password)
      expect(response.status).to eq(404), response.body
      expect_window_still_lapsed
    end

    it 'does not admit the path in another case', :aggregate_failures do
      response = reauthenticate_at('/api/colonel/REAUTHENTICATE', password)
      expect(response.status).to eq(404), response.body
      expect_window_still_lapsed
    end

    it 'treats a _method override as inert: the request stays a POST', :aggregate_failures do
      wrong = reauthenticate_at('/api/colonel/reauthenticate?_method=DELETE', 'not-the-password', _method: 'DELETE')
      expect(wrong.status).to eq(403), wrong.body
      expect(JSON.parse(wrong.body)).to include('error_code' => 'reauthentication_failed')
      expect_window_still_lapsed
    end

    it 'does not admit GET on the path, with or without an override', :aggregate_failures do
      get '/api/colonel/reauthenticate', { password: password, _method: 'POST' }, { 'HTTP_ACCEPT' => 'application/json' }
      expect(last_response.status).to eq(404), last_response.body
      expect_window_still_lapsed
    end
  end
end
