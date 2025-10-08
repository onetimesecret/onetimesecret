# spec/integration/dual_auth_mode_spec.rb
# Integration tests for dual authentication mode (basic/advanced)

require 'spec_helper'
require 'rack/test'
require 'json'

RSpec.describe 'Dual Authentication Mode Integration', type: :request do
  include Rack::Test::Methods

  def app
    @app ||= begin
      # Setup environment
      ENV['RACK_ENV'] = 'test'
      ENV['AUTHENTICATION_MODE'] = 'basic'
      ENV['REDIS_URL'] = 'redis://127.0.0.1:2121/0'

      # Boot application
      require_relative '../../lib/onetime'
      require_relative '../../lib/onetime/config'
      Onetime.boot! :test

      require_relative '../../lib/onetime/auth_config'
      require_relative '../../lib/onetime/middleware'
      require_relative '../../lib/onetime/application/registry'

      # Prepare registry
      Onetime::Application::Registry.prepare_application_registry

      # Return Core app (handles /auth/* in basic mode)
      Onetime::Application::Registry.mount_mappings['/'].new
    end
  end

  def json_response
    response = JSON.parse(last_response.body)
    # Handle wrapped responses: {"data": "{...}", "success": true}
    if response.is_a?(Hash) && response['data'].is_a?(String)
      JSON.parse(response['data'])
    else
      response
    end
  end

  def json_request_headers
    { 'HTTP_ACCEPT' => 'application/json' }
  end

  before(:all) do
    # Clear Redis before tests
    require 'redis'
    redis = Redis.new(url: 'redis://127.0.0.1:2121/0')
    redis.flushdb
  end

  describe 'Basic Mode Configuration' do
    it 'runs in basic mode' do
      expect(Onetime.auth_config.mode).to eq('basic')
    end

    it 'has advanced mode disabled' do
      expect(Onetime.auth_config.advanced_enabled?).to be false
    end

    it 'does not mount Auth app' do
      expect(Onetime::Application::Registry.mount_mappings.key?('/auth')).to be false
    end

    it 'mounts Core app at root' do
      expect(Onetime::Application::Registry.mount_mappings.key?('/')).to be true
    end
  end

  describe 'POST /auth/login' do
    context 'with invalid credentials' do
      it 'returns 401 status' do
        post '/auth/login',
          { u: 'nonexistent@example.com', p: 'wrongpassword' },
          json_request_headers

        expect(last_response.status).to eq(401)
      end

      it 'returns JSON response' do
        post '/auth/login',
          { u: 'nonexistent@example.com', p: 'wrongpassword' },
          json_request_headers

        expect(last_response.headers['Content-Type']).to include('application/json')
      end

      it 'returns error structure' do
        post '/auth/login',
          { u: 'nonexistent@example.com', p: 'wrongpassword' },
          json_request_headers

        response = json_response
        expect(response).to have_key('error')
        expect(response['error']).to be_a(String)
      end

      it 'returns field-error tuple' do
        post '/auth/login',
          { u: 'nonexistent@example.com', p: 'wrongpassword' },
          json_request_headers

        response = json_response
        expect(response).to have_key('field-error')
        expect(response['field-error']).to be_an(Array)
        expect(response['field-error'].length).to eq(2)
        expect(response['field-error'][0]).to eq('email')
        expect(response['field-error'][1]).to eq('invalid')
      end
    end

    context 'without JSON Accept header' do
      it 'redirects or returns HTML' do
        post '/auth/login',
          { u: 'test@example.com', p: 'password' }

        expect([302, 401, 500]).to include(last_response.status)
      end
    end
  end

  describe 'POST /auth/create-account' do
    context 'with incomplete data' do
      it 'returns validation error' do
        post '/auth/create-account',
          { u: 'incomplete@example.com' },
          json_request_headers

        expect([400, 401, 422]).to include(last_response.status)
        expect(last_response.headers['Content-Type']).to include('application/json')
      end
    end
  end

  describe 'POST /logout' do
    it 'accepts logout request' do
      post '/logout', {}, json_request_headers

      expect([200, 302]).to include(last_response.status)
    end

    context 'with JSON request' do
      it 'returns JSON response on success' do
        post '/logout', {}, json_request_headers

        if last_response.status == 200
          expect(last_response.headers['Content-Type']).to include('application/json')
        end
      end
    end
  end

  describe 'POST /auth/reset-password' do
    it 'accepts password reset request' do
      post '/auth/reset-password',
        { u: 'reset@example.com' },
        json_request_headers

      expect([200, 400, 422]).to include(last_response.status)
      expect(last_response.headers['Content-Type']).to include('application/json')
    end
  end

  describe 'POST /auth/reset-password/:key' do
    it 'accepts password reset with token' do
      post '/auth/reset-password/testtoken123',
        { p: 'newpassword123', password_confirm: 'newpassword123' },
        json_request_headers

      expect([400, 404, 422]).to include(last_response.status)
      expect(last_response.headers['Content-Type']).to include('application/json')
    end
  end

  describe 'Response Format Compatibility' do
    it 'uses Rodauth-compatible JSON format for errors' do
      post '/auth/login',
        { u: 'test@example.com', p: 'wrong' },
        json_request_headers

      response = json_response

      # Should have either 'success' or 'error' key
      expect(response.keys & ['success', 'error']).not_to be_empty

      # If error, should have field-error tuple
      if response.key?('error')
        expect(response).to have_key('field-error')
        expect(response['field-error']).to be_an(Array)
      end
    end
  end
end
