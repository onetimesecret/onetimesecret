# spec/integration/full/auth_enabled_kill_switch_spec.rb
#
# frozen_string_literal: true

# Integration tests for the AUTH_ENABLED master kill-switch on the /auth
# surface (#3911)
#
# When site.authentication.enabled is false, the request-level guard in
# Auth::Router darkens the entire /auth surface (404 with the shared
# ADR-013 body) before r.rodauth can process credentials or mint a
# session. Only /auth/health stays reachable. The mount itself is
# unchanged — Core routes.txt re-serves /auth/* paths, so the gate is
# per-request, not a registry unmount.
#
# Full-mode lane only: in simple mode the /auth mount is absent for an
# unrelated reason, so the guard is unobservable there.
#
# The guard reads Onetime::CustomDomain::SigninConfig.global_auth_enabled
# per request, and OT.conf is not deep-frozen in test mode
# (boot.rb skips freezing when OT.testing?), so these tests flip the
# switch by mutating OT.conf directly — no registry reset or re-boot.

require_relative '../integration_spec_helper'
require 'json'
require 'familia'

RSpec.describe 'Full Mode - AUTH_ENABLED kill switch', type: :integration do
  include Rack::Test::Methods

  def json_response
    JSON.parse(last_response.body)
  end

  # Headers for JSON API requests (Rodauth json-only mode requires both)
  def json_request_headers
    {
      'HTTP_ACCEPT' => 'application/json',
      'CONTENT_TYPE' => 'application/json'
    }
  end

  # Establish a session and retrieve CSRF token
  # Clear Content-Type before GET (Rack::Test persists it after POST)
  #
  # CsrfResponseHeader emits X-CSRF-Token on every response that carries a
  # session — including the guard's 404 — so the token is obtainable even
  # while the surface is dark. Sending it means the POST passes the
  # middleware-level AuthenticityToken check (which would otherwise 403
  # before the router runs) and the observed 404 is the router guard's.
  def fetch_csrf_token
    header 'Content-Type', nil
    header 'Accept', 'application/json'
    get '/auth'
    last_response.headers['X-CSRF-Token']
  end

  def post_login
    csrf_token = fetch_csrf_token

    env = json_request_headers.dup
    env['HTTP_X_CSRF_TOKEN'] = csrf_token if csrf_token

    post '/auth/login',
      { login: 'someone@example.com', password: 'SecureP@ssw0rd123', shrimp: csrf_token }.to_json,
      env
  end

  def app
    # MUST memoize - calling generate_rack_url_map multiple times corrupts app state
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  before(:all) do
    # Set full mode before loading the application
    ENV['AUTHENTICATION_MODE'] = 'full'

    # Reset registry to clear state from previous test runs
    Onetime::Application::Registry.reset!

    # Reload auth config to pick up AUTHENTICATION_MODE env var
    Onetime.auth_config.reload!

    # Boot application (skip if already booted by FullModeSuiteDatabase.setup!)
    Onetime.boot! :test unless Onetime.ready?

    # Prepare the application registry
    Onetime::Application::Registry.prepare_application_registry
  end

  after(:all) do
    ENV.delete('AUTHENTICATION_MODE')
  end

  let(:dbclient) { Familia.dbclient }

  context 'with AUTH_ENABLED=false' do
    before do
      @auth_conf        = OT.conf['site']['authentication']
      @original_enabled = @auth_conf['enabled']
      @auth_conf['enabled'] = false
    end

    after do
      @auth_conf['enabled'] = @original_enabled
    end

    describe 'POST /auth/login' do
      it 'returns 404' do
        post_login

        expect(last_response.status).to eq(404)
      end

      it 'returns the shared ADR-013 not-found body' do
        post_login

        expect(json_response).to eq('error' => 'Not Found', 'error_type' => 'NotFound')
      end

      it 'does not mint an authenticated session' do
        post_login

        # Only the rack session blob is a plain string; sidecar hashes and
        # index sorted sets also match '*session*' but are not GET-able.
        session_blobs = dbclient.keys('*session*').select { |key| dbclient.type(key) == 'string' }
        session_blobs.each do |key|
          session_data = dbclient.get(key)
          expect(session_data).not_to include('authenticated_at') if session_data
        end
      end
    end

    describe 'GET /auth/login' do
      it 'returns 404' do
        get '/auth/login', {}, { 'HTTP_ACCEPT' => 'application/json' }

        expect(last_response.status).to eq(404)
      end
    end

    describe 'GET /auth (root info)' do
      it 'returns 404 instead of the service info document' do
        get '/auth', {}, { 'HTTP_ACCEPT' => 'application/json' }

        expect(last_response.status).to eq(404)
      end
    end

    describe 'GET /auth/health' do
      it 'still serves the health check' do
        get '/auth/health', {}, { 'HTTP_ACCEPT' => 'application/json' }

        expect(last_response.status).to eq(200)
        expect(json_response['status']).to eq('ok')
      end
    end

    describe 'registry mount' do
      it 'keeps /auth mounted (guard is request-level, not a mount gate)' do
        expect(Onetime::Application::Registry.mount_mappings).to have_key('/auth')
      end
    end
  end

  context 'with AUTH_ENABLED restored to true' do
    before do
      @auth_conf        = OT.conf['site']['authentication']
      @original_enabled = @auth_conf['enabled']
      @auth_conf['enabled'] = true
    end

    after do
      @auth_conf['enabled'] = @original_enabled
    end

    it 'POST /auth/login reaches Rodauth again' do
      post_login

      # Any Rodauth response (200/400/401/redirect) proves the surface is
      # live; only the guard produces a 404 here.
      expect(last_response.status).not_to eq(404)
    end

    it 'GET /auth serves the service info document' do
      get '/auth', {}, { 'HTTP_ACCEPT' => 'application/json' }

      expect(last_response.status).to eq(200)
      expect(json_response['message']).to include('Authentication Service')
    end
  end
end
