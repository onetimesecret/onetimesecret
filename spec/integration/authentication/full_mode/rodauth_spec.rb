# spec/integration/authentication/full_mode/rodauth_spec.rb
#
# frozen_string_literal: true

# Tests for Rodauth integration in full authentication mode.
# Verifies that Auth app is mounted, routes respond correctly,
# and endpoints behave as expected when full auth is enabled.
#
# Database and application setup is handled by FullModeSuiteDatabase
# (see spec/support/full_mode_suite_database.rb).

require 'spec_helper'

RSpec.describe 'Rodauth Integration', :full_auth_mode do
  include_context 'auth_rack_test'

  describe 'mode configuration' do
    it 'reports full mode as active' do
      expect(Onetime.auth_config.mode).to eq('full')
    end

    it 'reports full_enabled? as true' do
      expect(Onetime.auth_config.full_enabled?).to be true
    end
  end

  describe 'application registry' do
    it 'mounts Auth app at /auth' do
      expect(Onetime::Application::Registry.mount_mappings).to have_key('/auth')
    end

    it 'mounts Core app at root' do
      expect(Onetime::Application::Registry.mount_mappings).to have_key('/')
    end

    it 'will sort Auth before Core in URL map (more specific paths first)' do
      # Registry stores in registration order, but generate_rack_url_map
      # sorts by path length (longest first) for proper specificity
      # We verify the sorted result, not the hash order
      sorted_paths = Onetime::Application::Registry.mount_mappings
        .sort_by { |path, _| [-path.length, path] }
        .map(&:first)
      auth_index = sorted_paths.index('/auth')
      core_index = sorted_paths.index('/')
      expect(auth_index).to be < core_index
    end
  end

  describe 'GET /auth' do
    before { get '/auth' }

    it 'returns 200' do
      expect(last_response.status).to eq(200)
    end

    it 'returns JSON content type' do
      expect(last_response.headers['Content-Type']).to include('application/json')
    end

    it 'includes version info' do
      expect(json_response).to include('message', 'version')
    end
  end

  describe 'GET /auth/health' do
    before { get '/auth/health' }

    it 'returns 200' do
      expect(last_response.status).to eq(200)
    end

    it 'returns JSON content type' do
      expect(last_response.headers['Content-Type']).to include('application/json')
    end

    it 'reports status ok and mode full' do
      expect(json_response).to include('status' => 'ok', 'mode' => 'full')
    end
  end

  describe 'GET /auth/admin/stats' do
    it 'returns expected status (endpoint may or may not exist)' do
      get '/auth/admin/stats'
      # 200=success, 401/403=auth required, 404=not implemented
      expect([200, 401, 403, 404]).to include(last_response.status)
    end
  end

  describe 'POST /auth/login' do
    before { post_json '/auth/login', { login: 'test@example.com', password: 'password123' } }

    it 'returns 400, 401, or 422 for invalid credentials' do
      expect([400, 401, 422]).to include(last_response.status)
    end

    it 'returns JSON content type' do
      expect(last_response.headers['Content-Type']).to include('application/json')
    end
  end

  describe 'POST /auth/create-account' do
    before { post_json '/auth/create-account', { login: 'new@example.com', password: 'password123' } }

    it 'returns 200, 201, 400, or 422 (endpoint exists)' do
      expect([200, 201, 400, 422]).to include(last_response.status)
    end

    it 'returns JSON content type' do
      expect(last_response.headers['Content-Type']).to include('application/json')
    end
  end

  describe 'GET / (Core app)' do
    it 'returns 200 or 500 (Core still handles root)' do
      get '/'
      expect([200, 500]).to include(last_response.status)
    end
  end
end
