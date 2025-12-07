# spec/integration/authentication/full_mode/active_sessions_spec.rb
#
# frozen_string_literal: true

# Integration tests for active sessions management in full auth mode.
# Tests the complete HTTP flow: account creation, login, session listing,
# and session management endpoints.
#
# These tests require full Rodauth integration with database support.
# The database setup must happen BEFORE the Auth app is loaded, so we
# do it in before(:all) rather than using the shared context.

require 'spec_helper'
require 'rack/test'
require 'sequel'
require 'bcrypt'

RSpec.describe 'Active Sessions Management', :full_auth_mode do
  include Rack::Test::Methods
  include AuthAccountFactory

  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  def json_response
    JSON.parse(last_response.body)
  end

  # Expose test_db for AuthAccountFactory methods
  def test_db
    @test_db
  end

  # POST/PUT/DELETE requests with body need Content-Type
  let(:json_headers) { { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' } }
  # GET requests don't have bodies - only set Accept header (Content-Type causes Rack::Parser errors)
  let(:accept_json) { { 'HTTP_ACCEPT' => 'application/json' } }
  let(:test_password) { 'Test1234!@' }

  before(:all) do
    require 'sequel'
    require 'auth/database'
    Sequel.extension :migration

    # Create in-memory SQLite database BEFORE booting
    @test_db = Sequel.sqlite

    # Run Rodauth migrations
    migrations_path = File.join(Onetime::HOME, 'apps', 'web', 'auth', 'migrations')
    Sequel::Migrator.run(@test_db, migrations_path)

    # Directly replace the connection method to return our test database
    # This must happen BEFORE prepare_application_registry
    # Capture in local variable for the closure
    test_database = @test_db
    Auth::Database.define_singleton_method(:connection) { test_database }

    require 'onetime'
    require 'onetime/config'
    Onetime.boot! :test
    require 'onetime/auth_config'
    require 'onetime/middleware'
    require 'onetime/application/registry'
    Onetime::Application::Registry.reset!
    Onetime::Application::Registry.prepare_application_registry
  end

  after(:all) do
    @test_db&.disconnect
  end

  # Helper to login via HTTP
  def login(email:, password: test_password)
    post '/auth/login', { login: email, password: password }.to_json, json_headers
    last_response.status == 200
  end

  describe 'authentication requirements' do
    it 'GET /auth/active-sessions returns 401 without session' do
      get '/auth/active-sessions', {}, accept_json
      expect(last_response.status).to eq(401)
    end

    it 'POST /auth/remove-all-active-sessions returns 401 without session' do
      post '/auth/remove-all-active-sessions', {}.to_json, json_headers
      expect(last_response.status).to eq(401)
    end
  end

  describe 'with authenticated session' do
    let(:test_email) { "sessions-test-#{SecureRandom.hex(8)}@example.com" }

    before do
      # Create account directly in database for faster setup
      @account = create_verified_account(db: test_db, email: test_email, password: test_password)
      # Login via HTTP to establish session
      login(email: test_email)
    end

    describe 'GET /auth/account' do
      before { get '/auth/account', {}, accept_json }

      it 'returns 200' do
        expect(last_response.status).to eq(200)
      end

      it 'includes active_sessions_count field' do
        expect(json_response).to have_key('active_sessions_count')
      end

      it 'reports at least 1 active session (current session)' do
        expect(json_response['active_sessions_count']).to be >= 1
      end
    end

    describe 'GET /auth/active-sessions' do
      before { get '/auth/active-sessions', {}, accept_json }

      it 'returns 200' do
        expect(last_response.status).to eq(200)
      end

      it 'contains sessions array' do
        expect(json_response).to have_key('sessions')
        expect(json_response['sessions']).to be_an(Array)
      end

      it 'has at least one session (current session)' do
        expect(json_response['sessions'].length).to be >= 1
      end

      it 'marks current session with is_current flag' do
        current = json_response['sessions'].find { |s| s['is_current'] }
        expect(current).not_to be_nil
      end

      it 'includes required session fields' do
        session = json_response['sessions'].first
        expect(session).to include('id', 'created_at', 'last_activity_at')
      end
    end

    describe 'DELETE /auth/active-sessions/:id (current session)' do
      it 'returns 400 when attempting to delete current session' do
        # Get current session ID
        get '/auth/active-sessions', {}, accept_json
        current_session_id = json_response['sessions'].find { |s| s['is_current'] }['id']

        delete "/auth/active-sessions/#{current_session_id}", {}.to_json, json_headers
        expect(last_response.status).to eq(400)
      end

      it 'includes error message about current session' do
        get '/auth/active-sessions', {}, accept_json
        current_session_id = json_response['sessions'].find { |s| s['is_current'] }['id']

        delete "/auth/active-sessions/#{current_session_id}", {}.to_json, json_headers
        expect(json_response['error']).to include('current session')
      end
    end

    describe 'POST /auth/remove-all-active-sessions' do
      before { post '/auth/remove-all-active-sessions', {}.to_json, json_headers }

      it 'returns 200' do
        expect(last_response.status).to eq(200)
      end

      it 'indicates success in response' do
        expect(json_response).to have_key('success')
      end

      it 'leaves only current session remaining' do
        get '/auth/active-sessions', {}, accept_json
        expect(json_response['sessions'].length).to eq(1)
      end

      it 'remaining session is marked as current' do
        get '/auth/active-sessions', {}, accept_json
        expect(json_response['sessions'].first['is_current']).to be true
      end
    end

    describe 'POST /auth/logout' do
      it 'returns 200' do
        post '/auth/logout', {}.to_json, json_headers
        expect(last_response.status).to eq(200)
      end

      it 'invalidates session (subsequent requests return 401)' do
        post '/auth/logout', {}.to_json, json_headers
        get '/auth/active-sessions', {}, accept_json
        expect(last_response.status).to eq(401)
      end
    end
  end
end
