# spec/integration/simple/password_change_session_rotation_spec.rb
#
# frozen_string_literal: true

# Simple-mode password change starts a new session id (#4466).
#
# POST /api/account/change-password in simple auth mode is
# AccountAPI::Logic::Account::UpdatePassword, not Rodauth. After the new
# passphrase is stored it calls rotate_session! (Onetime::Logic::Base), which
# sets `rack.session.options[:renew]`, and re-stamps the kept session past
# the credential watermark. The renewal itself happens at commit, in Rack's
# Abstract::Persisted#commit_session (rack-session 2.1): with :renew set it
# calls `delete_session(req, session.id, options)` and writes the session
# data under the id that call returns. On this store
# (Onetime::Session#delete_session) that call is the same step a logout
# takes: it writes the SessionEnded marker for the old id, deletes the old
# blob, purges its sidecar keys, and returns a fresh id.
#
# So what the old id is guaranteed here is what delete_session gives it: no
# blob, the ended marker set, and a request presenting the old cookie is not
# signed in. The session DATA crosses (unlike a sign-in, where nothing does),
# so the new id is signed in as the same customer without signing in again.
#
# The real session store runs underneath, as in login_session_rotation_spec.rb.

require_relative '../integration_spec_helper'
require_relative '../../support/customer_session_failure_matrix'

RSpec.describe 'Simple-mode password change starts a new session id (#4466)', type: :integration do
  include_context 'auth_rack_test'
  include CustomerSessionFailureMatrix

  let(:password) { 'Rotation-Change1234!' }
  let(:new_password) { 'Rotation-Changed5678!' }
  let(:db) { Familia.dbclient }
  let(:customer) do
    Onetime::Customer.new(email: "password-change-rotation-#{SecureRandom.hex(8)}@example.com").tap do |record|
      record.update_passphrase(password)
      record.verified = 'true'
      record.save
    end
  end
  let(:app) do
    @password_change_rotation_app ||= begin
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

  def blob_for(sid)
    key = session_store.find_key(db, sid)
    key && session_store.load_data(db, key, codec: session_codec)
  end

  def json_post(path, body, token)
    post path,
      body.merge(shrimp: token).to_json,
      {
        'CONTENT_TYPE' => 'application/json',
        'HTTP_ACCEPT' => 'application/json',
        'HTTP_X_CSRF_TOKEN' => token,
      }
    last_response
  end

  # GET /api/account/ (a session-authenticated route) for the given cookie, on
  # a fresh cookie jar so the current one is untouched.
  def account_read_for(sid)
    other = Rack::Test::Session.new(Rack::MockSession.new(app))
    other.set_cookie "onetime.session=#{sid}"
    other.get '/api/account/', {}, { 'HTTP_ACCEPT' => 'application/json' }
    other.last_response
  end

  it 'renews the id of the session it keeps and ends the old one', :aggregate_failures do
    login = json_post('/auth/login', { login: customer.email, password: password }, fetch_csrf_token)
    expect(login.status).to eq(200), login.body

    # The signed-in session the password is changed from.
    old_sid = current_session_id
    expect(old_sid).not_to be_nil
    expect(blob_for(old_sid)).to include('authenticated' => true, 'external_id' => customer.extid)

    change = json_post(
      '/api/account/change-password',
      { 'password' => password, 'newpassword' => new_password, 'password-confirm' => new_password },
      fetch_csrf_token,
    )
    expect(change.status).to eq(200), change.body

    watermark = Onetime::Customer.find_by_email(customer.email).last_password_update.to_i
    expect(watermark).to be_positive

    # A new id, and the old one ended the way delete_session ends it.
    new_sid = current_session_id
    expect(new_sid).not_to be_nil
    expect(new_sid).not_to eq(old_sid)
    expect(session_store.find_key(db, old_sid)).to be_nil
    expect(Onetime::SessionEnded.ended?(old_sid)).to be(true)

    # The session data crossed to the new id, re-stamped past the watermark.
    blob = blob_for(new_sid)
    expect(blob).to include('authenticated' => true, 'external_id' => customer.extid)
    expect(blob['authenticated_at'].to_i).to be > watermark

    new_read = account_read_for(new_sid)
    expect(new_read.status).to eq(200), new_read.body
    expect(JSON.parse(new_read.body)['user_id']).to eq(customer.extid)
    expect(account_read_for(old_sid).status).to eq(401)
  end
end
