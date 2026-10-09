# spec/integration/simple/login_session_rotation_spec.rb
#
# frozen_string_literal: true

# Simple-mode password sign-in starts a new session id (#4466).
#
# POST /auth/login in simple auth mode is served by
# Core::Controllers::Authentication, not Rodauth. Full mode renews the id at
# this step (login_session -> clear_session -> session.destroy,
# apps/web/auth/config/base.rb); these examples drive the simple-mode route
# end to end and check the same outcome there: the anonymous id the browser
# held before signing in is ended, the signed-in session lives under a new
# id, and nothing the previous occupant left in the session crosses over.
#
# The real session store runs underneath, so "ended" means what a logout
# means: no blob under the old id, and a request presenting the old cookie
# is not signed in.

require_relative '../integration_spec_helper'
require_relative '../../support/customer_session_failure_matrix'

RSpec.describe 'Simple-mode password sign-in starts a new session id (#4466)', type: :integration do
  include_context 'auth_rack_test'
  include CustomerSessionFailureMatrix

  let(:password) { 'Rotation-Simple1234!' }
  let(:db) { Familia.dbclient }
  let(:app) do
    @simple_login_rotation_app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  before(:all) do
    Onetime.boot! :test
  end

  before do
    skip 'requires simple auth mode' unless Onetime.auth_config.simple_enabled?

    clear_cookies
  end

  def create_customer(verified:)
    customer = Onetime::Customer.new(email: "login-rotation-#{SecureRandom.hex(8)}@example.com")
    customer.update_passphrase(password)
    customer.verified = verified ? 'true' : 'false'
    customer.save
    customer
  end

  # The anonymous session a browser holds before it signs in, with the CSRF
  # token that session issued.
  #
  # @return [Array(String, String)] the session id and the masked token
  def anonymous_session!
    token = fetch_csrf_token
    sid   = current_session_id
    expect(sid).not_to be_nil
    expect(blob_for(sid)).not_to be_nil
    [sid, token]
  end

  def login!(customer, token, extra = {})
    post '/auth/login',
      { login: customer.email, password: password, shrimp: token }.merge(extra).to_json,
      {
        'CONTENT_TYPE' => 'application/json',
        'HTTP_ACCEPT' => 'application/json',
        'HTTP_X_CSRF_TOKEN' => token,
      }
    last_response
  end

  def blob_for(sid)
    key = session_store.find_key(db, sid)
    key && session_store.load_data(db, key, codec: session_codec)
  end

  # Status of a session-authenticated API route for the given cookie, on a
  # fresh cookie jar so the current one is untouched.
  def account_status_for(sid)
    other = Rack::Test::Session.new(Rack::MockSession.new(app))
    other.set_cookie "onetime.session=#{sid}"
    other.get '/api/account/', {}, { 'HTTP_ACCEPT' => 'application/json' }
    other.last_response.status
  end

  def update_preference(token)
    post '/api/account/update-notification-preference',
      { field: 'notify_on_reveal', value: 'true', shrimp: token }.to_json,
      {
        'CONTENT_TYPE' => 'application/json',
        'HTTP_ACCEPT' => 'application/json',
        'HTTP_X_CSRF_TOKEN' => token,
      }
    last_response
  end

  # State a previous occupant of this browser left in the anonymous session:
  # an ordinary key, a remember-me deadline, and a colonel step-up window
  # (an externalized sidecar field, merged into the hash when it is read).
  def seed_previous_occupant!(sid)
    rewrite_session_blob do |data|
      data['seeded_by_previous_occupant'] = 'yes'
      data[Onetime::RememberMe::SESSION_KEY] = Familia.now.to_i + 3600
    end
    Onetime::SessionSidecar.write(
      sid, 'elevated_until', { 'extid' => 'ur_previous_occupant', 'exp' => Familia.now.to_i + 600 }
    )
    expect(Onetime::SessionSidecar.read(sid, 'elevated_until')).not_to be_nil
  end

  shared_examples 'a sign-in that starts a new session id' do
    it 'signs in under a new id and ends the old one', :aggregate_failures do
      old_sid, token = anonymous_session!

      expect(login!(customer, token).status).to eq(200), last_response.body

      new_sid = current_session_id
      expect(new_sid).not_to be_nil
      expect(new_sid).not_to eq(old_sid)
      expect(session_store.find_key(db, old_sid)).to be_nil
      expect(Onetime::SessionEnded.ended?(old_sid)).to be(true)

      blob = blob_for(new_sid)
      expect(blob).to include('authenticated' => true, 'external_id' => customer.extid)
    end

    it 'carries nothing the previous occupant left in the session', :aggregate_failures do
      old_sid, token = anonymous_session!
      seed_previous_occupant!(old_sid)

      expect(login!(customer, token).status).to eq(200), last_response.body

      new_sid = current_session_id
      blob    = blob_for(new_sid)
      expect(blob).to include('external_id' => customer.extid)
      expect(blob).not_to have_key('seeded_by_previous_occupant')
      expect(blob).not_to have_key(Onetime::RememberMe::SESSION_KEY)
      expect(blob).not_to have_key('elevated_until')
      expect(Onetime::SessionSidecar.read(new_sid, 'elevated_until')).to be_nil
      expect(Onetime::SessionSidecar.read(old_sid, 'elevated_until')).to be_nil
    end
  end

  context 'with a verified account' do
    let(:customer) { create_customer(verified: true) }

    include_examples 'a sign-in that starts a new session id'

    it 'leaves the old cookie signed out on a session-authenticated route', :aggregate_failures do
      old_sid, token = anonymous_session!
      expect(login!(customer, token).status).to eq(200), last_response.body
      new_sid = current_session_id

      expect(account_status_for(new_sid)).to eq(200)
      expect(account_status_for(old_sid)).to eq(401)
    end

    it 'still applies the remember-me choice made at this sign-in' do
      _old_sid, token = anonymous_session!
      expect(login!(customer, token, 'remember-me' => true).status).to eq(200), last_response.body

      expect(blob_for(current_session_id)[Onetime::RememberMe::SESSION_KEY])
        .to be_within(5).of(Familia.now.to_i + Onetime::RememberMe::DURATION)
    end

    it 'returns a CSRF token for the new session, and the pre-sign-in one stops working', :aggregate_failures do
      _old_sid, old_token = anonymous_session!
      expect(login!(customer, old_token).status).to eq(200), last_response.body

      new_token = last_response.headers['X-CSRF-Token']
      expect(new_token).not_to be_nil
      expect(new_token).not_to be_empty

      expect(update_preference(old_token).status).to eq(403)
      expect(update_preference(new_token).status).to eq(200), last_response.body
    end
  end

  context 'with a pending (unverified) account' do
    let(:customer) { create_customer(verified: false) }

    before { expect(customer.pending?).to be(true) }

    include_examples 'a sign-in that starts a new session id'
  end

  # The login must not succeed on a session whose old id could not be ended:
  # the request answers with an error, and no session under either id is
  # signed in.
  describe 'when the old id cannot be ended' do
    let(:customer) { create_customer(verified: true) }

    def expect_refused_without_an_authenticated_session(old_sid)
      expect(last_response.status).to eq(503)
      expect(json_response).to include('error')
      expect(json_response).not_to have_key('success')

      [old_sid, current_session_id].uniq.each do |sid|
        blob = blob_for(sid)
        expect(blob.to_h['authenticated']).not_to be(true)
        expect(blob.to_h).not_to have_key('external_id')
        expect(account_status_for(sid)).to eq(401)
      end
    end

    it 'refuses the login when the ended marker cannot be written', :aggregate_failures do
      old_sid, token = anonymous_session!
      allow(Onetime::SessionEnded).to receive(:mark).and_return(false)

      login!(customer, token)

      expect(current_session_id).to eq(old_sid)
      expect_refused_without_an_authenticated_session(old_sid)
    end

    it 'refuses the login when the rotation reports itself incomplete after re-keying', :aggregate_failures do
      old_sid, token = anonymous_session!
      allow(Onetime::SessionRotation).to receive(:rotate!).and_wrap_original do |original, *args, **kwargs|
        result          = original.call(*args, **kwargs)
        result.complete = false
        result.reason   = :blob_survived
        result
      end

      login!(customer, token)

      expect(current_session_id).not_to eq(old_sid)
      expect_refused_without_an_authenticated_session(old_sid)
    end
  end
end
