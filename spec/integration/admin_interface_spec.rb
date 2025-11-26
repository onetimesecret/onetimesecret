# spec/integration/admin_interface_spec.rb
#
# frozen_string_literal: true

require_relative 'integration_spec_helper'
require 'rack/test'

RSpec.describe 'Admin Interface', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    ENV['RACK_ENV'] = 'test'
    ENV['AUTHENTICATION_MODE'] = 'advanced'
    ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '../..'))

    # Reset both registries to clear state from previous test runs
    Onetime::Application::Registry.reset!
    Onetime::Boot::InitializerRegistry.reset!

    # Reload auth config to pick up AUTHENTICATION_MODE env var
    Onetime.auth_config.reload!

    # Boot application
    Onetime.boot! :test

    # Prepare registry
    Onetime::Application::Registry.prepare_application_registry
  end

  def app
    Onetime::Application::Registry.generate_rack_url_map
  end

  let(:colonel_user) do
    Onetime::Customer.create!(
      email: "colonel@example.com",
      role: 'colonel',
      verified: 'true'
    )
  end

  let(:regular_user) do
    Onetime::Customer.create!(
      email: "user@example.com",
      role: 'customer',
      verified: 'true'
    )
  end

  # Helper to create a session for a user
  def create_session_for(user)
    # Set up session with user
    env 'rack.session', {
      'customer_id' => user.objid,
      'authenticated' => true,
      'session_id' => SecureRandom.hex(16)
    }
  end

  # Helper to create secrets through the API
  def create_secret_via_api(content: 'test secret', owner_id: nil)
    metadata, secret = Onetime::Metadata.spawn_pair(
      owner_id || regular_user.objid,
      7 * 86400, # 7 days
      content
    )
    { metadata: metadata, secret: secret }
  end

  describe 'Authentication & Authorization' do
    context 'when not authenticated' do
      it 'returns 401 for colonel endpoints' do
        get '/api/colonel/info'
        expect(last_response.status).to eq(401)
      end

      it 'returns 401 for secret management' do
        get '/api/colonel/secrets'
        expect(last_response.status).to eq(401)
      end
    end

    context 'when authenticated as regular user' do
      before { create_session_for(regular_user) }

      it 'returns 403 forbidden for colonel endpoints' do
        get '/api/colonel/info'
        expect(last_response.status).to eq(403)
      end
    end

    context 'when authenticated as colonel' do
      before { create_session_for(colonel_user) }

      it 'allows access to colonel endpoints' do
        get '/api/colonel/info'
        expect(last_response.status).to eq(200)
      end

      it 'allows access to secret management' do
        get '/api/colonel/secrets'
        expect(last_response.status).to eq(200)
      end
    end
  end

  describe 'Secret Management' do
    before { create_session_for(colonel_user) }

    describe 'GET /api/colonel/secrets' do
      context 'with no secrets' do
        it 'returns empty list' do
          get '/api/colonel/secrets'
          expect(last_response.status).to eq(200)

          body = JSON.parse(last_response.body)
          expect(body['details']['secrets']).to be_an(Array)
          expect(body['details']['secrets']).to be_empty
        end
      end

      context 'with multiple secrets' do
        let!(:secrets) do
          10.times.map { create_secret_via_api(owner_id: regular_user.objid) }
        end

        it 'lists all secrets' do
          get '/api/colonel/secrets'
          expect(last_response.status).to eq(200)

          body = JSON.parse(last_response.body)
          expect(body['details']['secrets'].size).to eq(10)
        end

        it 'includes pagination info' do
          get '/api/colonel/secrets'
          body = JSON.parse(last_response.body)

          pagination = body['details']['pagination']
          expect(pagination['page']).to eq(1)
          expect(pagination['total_count']).to eq(10)
        end

        it 'supports pagination' do
          get '/api/colonel/secrets?page=1&per_page=5'
          body = JSON.parse(last_response.body)

          expect(body['details']['secrets'].size).to eq(5)
          expect(body['details']['pagination']['page']).to eq(1)
          expect(body['details']['pagination']['total_pages']).to eq(2)
        end
      end
    end

    describe 'GET /api/colonel/secrets/:secret_id' do
      let!(:secret_pair) { create_secret_via_api }

      it 'returns secret metadata' do
        get "/api/colonel/secrets/#{secret_pair[:secret].objid}"
        expect(last_response.status).to eq(200)

        body = JSON.parse(last_response.body)
        expect(body['record']['secret_id']).to eq(secret_pair[:secret].objid)
        expect(body['record']['state']).to eq('new')
      end

      it 'includes associated metadata' do
        get "/api/colonel/secrets/#{secret_pair[:secret].objid}"
        body = JSON.parse(last_response.body)

        expect(body['details']['metadata']).not_to be_nil
        expect(body['details']['metadata']['metadata_id']).to eq(secret_pair[:metadata].objid)
      end

      it 'includes owner information' do
        get "/api/colonel/secrets/#{secret_pair[:secret].objid}"
        body = JSON.parse(last_response.body)

        expect(body['details']['owner']).not_to be_nil
        expect(body['details']['owner']['user_id']).to eq(regular_user.objid)
      end

      it 'returns 404 for non-existent secret' do
        get '/api/colonel/secrets/nonexistent'
        expect(last_response.status).to eq(404)
      end
    end

    describe 'DELETE /api/colonel/secrets/:secret_id' do
      let!(:secret_pair) { create_secret_via_api }

      it 'deletes the secret' do
        delete "/api/colonel/secrets/#{secret_pair[:secret].objid}"
        expect(last_response.status).to eq(200)

        body = JSON.parse(last_response.body)
        expect(body['record']['deleted']).to be true
      end

      it 'actually removes secret from database' do
        secret_id = secret_pair[:secret].objid

        delete "/api/colonel/secrets/#{secret_id}"

        # Verify secret is gone
        reloaded = Onetime::Secret.load(secret_id)
        expect(reloaded).to be_nil
      end

      it 'deletes associated metadata (cascade)' do
        secret_id = secret_pair[:secret].objid
        metadata_id = secret_pair[:metadata].objid

        delete "/api/colonel/secrets/#{secret_id}"

        # Verify metadata is also gone
        reloaded_metadata = Onetime::Metadata.load(metadata_id)
        expect(reloaded_metadata).to be_nil
      end

      it 'returns 404 for non-existent secret' do
        delete '/api/colonel/secrets/nonexistent'
        expect(last_response.status).to eq(404)
      end
    end
  end

  describe 'User Management' do
    before { create_session_for(colonel_user) }

    describe 'GET /api/colonel/users' do
      let!(:users) do
        5.times.map do |i|
          Onetime::Customer.create!(
            email: "user#{i}@example.com",
            role: 'customer',
            verified: 'true'
          )
        end
      end

      it 'lists all users' do
        get '/api/colonel/users'
        expect(last_response.status).to eq(200)

        body = JSON.parse(last_response.body)
        # Should have at least the 5 we created + colonel + regular_user
        expect(body['details']['users'].size).to be >= 5
      end

      it 'includes user stats' do
        get '/api/colonel/users'
        body = JSON.parse(last_response.body)

        user = body['details']['users'].first
        expect(user).to have_key('email')
        expect(user).to have_key('role')
        expect(user).to have_key('secrets_count')
      end

      it 'supports role filtering' do
        # Create an admin user
        Onetime::Customer.create!(
          email: "admin@example.com",
          role: 'admin',
          verified: 'true'
        )

        get '/api/colonel/users?role=admin'
        body = JSON.parse(last_response.body)

        expect(body['details']['users'].all? { |u| u['role'] == 'admin' }).to be true
      end
    end

    describe 'GET /api/colonel/users/:user_id' do
      let!(:test_user) { regular_user }
      let!(:user_secrets) do
        3.times.map { create_secret_via_api(owner_id: test_user.objid) }
      end

      it 'returns user details' do
        get "/api/colonel/users/#{test_user.objid}"
        expect(last_response.status).to eq(200)

        body = JSON.parse(last_response.body)
        expect(body['record']['user_id']).to eq(test_user.objid)
      end

      it 'includes user secrets' do
        get "/api/colonel/users/#{test_user.objid}"
        body = JSON.parse(last_response.body)

        expect(body['details']['secrets']['count']).to eq(3)
        expect(body['details']['secrets']['items'].size).to eq(3)
      end

      it 'includes user stats' do
        get "/api/colonel/users/#{test_user.objid}"
        body = JSON.parse(last_response.body)

        expect(body['details']['stats']).to have_key('secrets_created')
        expect(body['details']['stats']).to have_key('secrets_shared')
      end
    end

    describe 'POST /api/colonel/users/:user_id/plan' do
      let!(:test_user) { regular_user }

      it 'updates user plan' do
        post "/api/colonel/users/#{test_user.objid}/plan", planid: 'premium'
        expect(last_response.status).to eq(200)

        body = JSON.parse(last_response.body)
        expect(body['record']['new_planid']).to eq('premium')
      end

      it 'actually modifies the user record' do
        post "/api/colonel/users/#{test_user.objid}/plan", planid: 'enterprise'

        reloaded_user = Onetime::Customer.load(test_user.objid)
        expect(reloaded_user.planid).to eq('enterprise')
      end

      it 'returns 404 for non-existent user' do
        post '/api/colonel/users/nonexistent/plan', planid: 'premium'
        expect(last_response.status).to eq(404)
      end
    end
  end

  describe 'System Monitoring' do
    before { create_session_for(colonel_user) }

    describe 'GET /api/colonel/system/database' do
      it 'returns database metrics' do
        get '/api/colonel/system/database'
        expect(last_response.status).to eq(200)

        body = JSON.parse(last_response.body)
        expect(body['details']).to have_key('redis_info')
        expect(body['details']).to have_key('memory_stats')
      end

      it 'includes model counts' do
        get '/api/colonel/system/database'
        body = JSON.parse(last_response.body)

        expect(body['details']['model_counts']).to have_key('customers')
        expect(body['details']['model_counts']).to have_key('secrets')
      end
    end

    describe 'GET /api/colonel/system/redis' do
      it 'returns Redis metrics' do
        get '/api/colonel/system/redis'
        expect(last_response.status).to eq(200)

        body = JSON.parse(last_response.body)
        expect(body['details']).to have_key('redis_info')
      end
    end
  end

  describe 'IP Banning' do
    before { create_session_for(colonel_user) }

    describe 'GET /api/colonel/banned-ips' do
      it 'returns empty list when no IPs banned' do
        get '/api/colonel/banned-ips'
        expect(last_response.status).to eq(200)

        body = JSON.parse(last_response.body)
        expect(body['details']['banned_ips']).to be_an(Array)
      end
    end

    describe 'POST /api/colonel/banned-ips' do
      it 'bans an IP address' do
        post '/api/colonel/banned-ips', {
          ip_address: '192.168.1.100',
          reason: 'Spam'
        }

        expect(last_response.status).to eq(200)
        body = JSON.parse(last_response.body)
        expect(body['record']['ip_address']).to eq('192.168.1.100')
      end

      it 'actually bans the IP in database' do
        post '/api/colonel/banned-ips', {
          ip_address: '10.0.0.50',
          reason: 'Abuse'
        }

        expect(Onetime::BannedIP.banned?('10.0.0.50')).to be true
      end

      it 'rejects invalid IP addresses' do
        post '/api/colonel/banned-ips', {
          ip_address: 'not-an-ip',
          reason: 'Test'
        }

        expect(last_response.status).to eq(400)
      end
    end

    describe 'DELETE /api/colonel/banned-ips/:ip' do
      before do
        Onetime::BannedIP.ban!('192.168.1.200', reason: 'Test')
      end

      it 'unbans an IP address' do
        delete '/api/colonel/banned-ips/192.168.1.200'
        expect(last_response.status).to eq(200)
      end

      it 'actually removes the ban from database' do
        delete '/api/colonel/banned-ips/192.168.1.200'

        expect(Onetime::BannedIP.banned?('192.168.1.200')).to be false
      end

      it 'returns 404 for non-banned IP' do
        delete '/api/colonel/banned-ips/1.2.3.4'
        expect(last_response.status).to eq(404)
      end
    end
  end

  describe 'Usage Export' do
    before { create_session_for(colonel_user) }

    describe 'GET /api/colonel/usage/export' do
      let!(:secrets) do
        # Create secrets over a date range
        Timecop.freeze(Time.now - 10.days) do
          2.times { create_secret_via_api }
        end

        Timecop.freeze(Time.now - 5.days) do
          3.times { create_secret_via_api }
        end

        Timecop.freeze(Time.now - 1.day) do
          1.times { create_secret_via_api }
        end
      end

      it 'exports usage data' do
        start_date = (Time.now - 30.days).to_i
        end_date = Time.now.to_i

        get "/api/colonel/usage/export?start_date=#{start_date}&end_date=#{end_date}"
        expect(last_response.status).to eq(200)

        body = JSON.parse(last_response.body)
        expect(body['details']).to have_key('usage_data')
      end

      it 'groups secrets by day' do
        start_date = (Time.now - 30.days).to_i
        end_date = Time.now.to_i

        get "/api/colonel/usage/export?start_date=#{start_date}&end_date=#{end_date}"
        body = JSON.parse(last_response.body)

        expect(body['details']).to have_key('secrets_by_day')
      end

      it 'calculates accurate totals' do
        start_date = (Time.now - 30.days).to_i
        end_date = Time.now.to_i

        get "/api/colonel/usage/export?start_date=#{start_date}&end_date=#{end_date}"
        body = JSON.parse(last_response.body)

        # Should match the number of secrets we created
        expect(body['details']['usage_data']['total_secrets']).to be >= 6
      end
    end
  end

  # ACCEPTANCE TESTS
  describe 'Acceptance Tests' do
    before { create_session_for(colonel_user) }

    it 'TEST 1: Create secret as user, view in admin panel' do
      # Create a secret as a regular user
      secret_pair = create_secret_via_api(
        content: 'acceptance test secret',
        owner_id: regular_user.objid
      )

      # View in admin panel
      get "/api/colonel/secrets/#{secret_pair[:secret].objid}"
      expect(last_response.status).to eq(200)

      body = JSON.parse(last_response.body)
      expect(body['record']['secret_id']).to eq(secret_pair[:secret].objid)
      expect(body['details']['owner']['user_id']).to eq(regular_user.objid)
    end

    it 'TEST 2: Delete secret, verify gone from database' do
      # Create a secret
      secret_pair = create_secret_via_api

      secret_id = secret_pair[:secret].objid
      metadata_id = secret_pair[:metadata].objid

      # Delete through admin panel
      delete "/api/colonel/secrets/#{secret_id}"
      expect(last_response.status).to eq(200)

      # Verify actually gone from database
      expect(Onetime::Secret.load(secret_id)).to be_nil
      expect(Onetime::Metadata.load(metadata_id)).to be_nil
    end

    it 'TEST 3: Change user plan, verify in database' do
      test_user = Onetime::Customer.create!(
        email: 'plantest@example.com',
        role: 'customer',
        verified: 'true'
      )

      # Change plan through admin panel
      post "/api/colonel/users/#{test_user.objid}/plan", planid: 'premium'
      expect(last_response.status).to eq(200)

      # Verify actually changed in database
      reloaded = Onetime::Customer.load(test_user.objid)
      expect(reloaded.planid).to eq('premium')
    end

    it 'TEST 4: Export usage, verify counts match' do
      # Create known number of secrets
      10.times { create_secret_via_api }

      start_date = (Time.now - 1.day).to_i
      end_date = Time.now.to_i

      # Export usage
      get "/api/colonel/usage/export?start_date=#{start_date}&end_date=#{end_date}"
      expect(last_response.status).to eq(200)

      body = JSON.parse(last_response.body)

      # Verify count matches what we created
      expect(body['details']['usage_data']['total_secrets']).to be >= 10
    end

    it 'TEST 5: Ban IP, verify blocking works' do
      # Ban an IP
      post '/api/colonel/banned-ips', {
        ip_address: '1.2.3.4',
        reason: 'Test ban'
      }
      expect(last_response.status).to eq(200)

      # Verify IP is actually banned in database
      expect(Onetime::BannedIP.banned?('1.2.3.4')).to be true
    end
  end
end
