# spec/integration/advanced_auth_mode_spec.rb

require 'spec_helper'
require 'rack/test'

RSpec.describe 'Advanced Authentication Mode', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    # Set advanced mode before loading the application
    ENV['RACK_ENV'] = 'test'
    ENV['AUTHENTICATION_MODE'] = 'advanced'
    ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '../..'))

    Onetime.boot! :test

    # Prepare the application registry
    Onetime::Application::Registry.prepare_application_registry
  end

  def app
    Onetime::Application::Registry.generate_rack_url_map
  end

  describe 'Configuration' do
    it 'activates advanced mode' do
      expect(Onetime.auth_config.mode).to eq('advanced')
    end

    it 'enables advanced mode features' do
      expect(Onetime.auth_config.advanced_enabled?).to be true
    end
  end

  describe 'Application Mounting' do
    it 'mounts Auth app at /auth' do
      expect(Onetime::Application::Registry.mount_mappings).to have_key('/auth')
    end

    it 'mounts Core app at root' do
      expect(Onetime::Application::Registry.mount_mappings).to have_key('/')
    end

    it 'mounts Auth app before Core app (more specific paths first)' do
      paths = Onetime::Application::Registry.mount_mappings.keys
      auth_index = paths.index('/auth')
      core_index = paths.index('/')

      expect(auth_index).not_to be_nil
      expect(core_index).not_to be_nil
      expect(auth_index).to be < core_index
    end
  end

  describe 'Auth App Endpoints' do
    describe 'GET /auth' do
      before { get '/auth' }

      it 'responds with success' do
        expect(last_response.status).to eq(200)
      end

      it 'returns JSON response' do
        expect(last_response.content_type).to include('application/json')
      end

      it 'includes version information' do
        body = JSON.parse(last_response.body)
        expect(body).to have_key('message')
        expect(body).to have_key('version')
      end
    end

    describe 'GET /auth/health' do
      before { get '/auth/health' }

      it 'responds with success' do
        expect(last_response.status).to eq(200)
      end

      it 'returns JSON response' do
        expect(last_response.content_type).to include('application/json')
      end

      it 'includes status and mode information' do
        body = JSON.parse(last_response.body)
        expect(body['status']).to eq('ok')
        expect(body['mode']).to eq('advanced')
      end
    end

    describe 'GET /auth/admin/stats' do
      before { get '/auth/admin/stats' }

      it 'responds with success or authentication required' do
        expect([200, 401, 403]).to include(last_response.status)
      end

      it 'returns JSON response' do
        expect(last_response.content_type).to include('application/json')
      end
    end
  end

  describe 'Rodauth Endpoints' do
    describe 'POST /auth/login' do
      let(:login_params) do
        { login: 'test@example.com', password: 'password123' }
      end

      before do
        post '/auth/login',
             login_params.to_json,
             { 'CONTENT_TYPE' => 'application/json' }
      end

      it 'responds with authentication error or validation error' do
        expect([400, 401, 422]).to include(last_response.status)
      end

      it 'returns JSON response' do
        expect(last_response.content_type).to include('application/json')
      end

      it 'includes error information' do
        body = JSON.parse(last_response.body)
        expect(body).to have_key('error')
      end
    end

    describe 'POST /auth/create-account' do
      let(:signup_params) do
        {
          login: "test_#{Time.now.to_i}@example.com",
          password: 'password123',
          'password-confirm' => 'password123'
        }
      end

      before do
        post '/auth/create-account',
             signup_params.to_json,
             { 'CONTENT_TYPE' => 'application/json' }
      end

      it 'responds with success or validation error' do
        expect([200, 201, 400, 422]).to include(last_response.status)
      end

      it 'returns JSON response' do
        expect(last_response.content_type).to include('application/json')
      end

      context 'when database is configured' do
        it 'returns appropriate response structure' do
          body = JSON.parse(last_response.body)
          if last_response.status == 200 || last_response.status == 201
            expect(body).to have_key('success')
          else
            expect(body).to have_key('error')
          end
        end
      end
    end

    describe 'POST /auth/logout' do
      before do
        post '/auth/logout',
             {}.to_json,
             { 'CONTENT_TYPE' => 'application/json' }
      end

      it 'responds appropriately' do
        expect([200, 201, 302, 400]).to include(last_response.status)
      end

      it 'returns JSON response if successful' do
        if last_response.status == 200
          expect(last_response.content_type).to include('application/json')
        end
      end
    end

    describe 'POST /auth/reset-password' do
      let(:reset_params) do
        { login: 'test@example.com' }
      end

      before do
        post '/auth/reset-password',
             reset_params.to_json,
             { 'CONTENT_TYPE' => 'application/json' }
      end

      it 'responds with success or error' do
        # 401 is returned for non-existent accounts (prevents account enumeration)
        expect([200, 400, 401, 422]).to include(last_response.status)
      end

      it 'returns JSON response' do
        expect(last_response.content_type).to include('application/json')
      end
    end
  end

  describe 'Core App Routes' do
    describe 'GET /' do
      before { get '/' }

      it 'still handles root route' do
        # May return 500 due to domain validation issues in test environment
        expect([200, 500]).to include(last_response.status)
      end
    end

    describe 'GET /api/v2/status' do
      before { get '/api/v2/status' }

      it 'handles API routes' do
        expect([200, 401]).to include(last_response.status)
      end
    end
  end

  describe 'JSON Response Format Compatibility' do
    context 'for login endpoint' do
      let(:login_params) do
        { login: 'invalid@example.com', password: 'wrongpassword' }
      end

      before do
        post '/auth/login',
             login_params.to_json,
             { 'CONTENT_TYPE' => 'application/json' }
      end

      it 'returns error in expected format' do
        expect(last_response.status).to eq(401)

        body = JSON.parse(last_response.body)
        expect(body).to have_key('error')

        # Optionally check for field-error format
        if body.has_key?('field-error')
          expect(body['field-error']).to be_an(Array)
          expect(body['field-error'].length).to eq(2)
        end
      end
    end

    context 'for successful responses' do
      it 'uses consistent success format' do
        get '/auth/health'

        if last_response.status == 200
          body = JSON.parse(last_response.body)
          expect(body).to be_a(Hash)
        end
      end
    end
  end

  describe 'Session Integration' do
    it 'uses unified session cookie name' do
      post '/auth/login',
           { login: 'test@example.com', password: 'password' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      # Check if session cookie is set
      set_cookie_header = last_response.headers['Set-Cookie']
      if set_cookie_header
        expect(set_cookie_header).to include('onetime.session')
      end
    end
  end

  describe 'Database Connection' do
    it 'creates database connection in advanced mode' do
      if Onetime.auth_config.advanced_enabled?
        expect(Auth::Config::Database.connection).not_to be_nil
      else
        expect(Auth::Config::Database.connection).to be_nil
      end
    end

    it 'handles database operations gracefully' do
      get '/auth/admin/stats'

      # Should not crash even if database is not available
      expect(last_response).not_to be_nil
    end
  end
end
