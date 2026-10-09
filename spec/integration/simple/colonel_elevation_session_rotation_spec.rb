# spec/integration/simple/colonel_elevation_session_rotation_spec.rb
#
# frozen_string_literal: true

# Colonel step-up starts a new session id in simple auth mode (#4466).
#
# The simple-mode twin of
# spec/integration/full/colonel_elevation_session_rotation_spec.rb: a
# colonel signs in through POST /auth/login (Core::Controllers::Authentication),
# steps up through POST /api/colonel/elevation, and the window lands under a
# new session id while the operator stays signed in.

require_relative '../integration_spec_helper'
require_relative '../../support/customer_session_failure_matrix'

RSpec.describe 'Simple-mode colonel step-up starts a new session id (#4466)', type: :integration do
  include_context 'auth_rack_test'
  include CustomerSessionFailureMatrix

  let(:password) { 'Elevation-Simple1234!' }
  let(:db) { Familia.dbclient }
  let(:app) do
    @simple_elevation_rotation_app ||= begin
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

    stub_colonel_elevation(enabled: true, window: 600)
    clear_cookies
  end

  let(:colonel) do
    customer = Onetime::Customer.new(email: "elevation-simple-#{SecureRandom.hex(8)}@example.com")
    customer.update_passphrase(password)
    customer.role     = 'colonel'
    customer.verified = 'true'
    customer.save
    customer
  end

  def sign_in!
    post_json '/auth/login', { login: colonel.email, password: password }
    expect(last_response.status).to eq(200), last_response.body
  end

  def blob_for(sid)
    key = session_store.find_key(db, sid)
    key && session_store.load_data(db, key, codec: session_codec)
  end

  def elevation_status_for(sid)
    other = Rack::Test::Session.new(Rack::MockSession.new(app))
    other.set_cookie "onetime.session=#{sid}"
    other.get '/api/colonel/elevation', {}, { 'HTTP_ACCEPT' => 'application/json' }
    other.last_response
  end

  it 'writes the window under a new id, keeps the operator signed in, and signs the old cookie out', :aggregate_failures do
    sign_in!
    old_sid = current_session_id

    post_json '/api/colonel/elevation', { factor: 'password', password: password }
    expect(last_response.status).to eq(200), last_response.body

    new_sid = current_session_id
    expect(new_sid).not_to eq(old_sid)
    expect(session_store.find_key(db, old_sid)).to be_nil
    expect(blob_for(new_sid)).to include('authenticated' => true, 'external_id' => colonel.extid)

    current = elevation_status_for(new_sid)
    expect(current.status).to eq(200), current.body
    expect(JSON.parse(current.body).dig('record', 'elevated')).to be(true)

    expect(elevation_status_for(old_sid).status).to eq(401)
  end
end
