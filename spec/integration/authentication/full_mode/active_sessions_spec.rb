# Generated rspec code for /Users/d/Projects/opensource/onetime/onetimesecret/try/integration/authentication/full_mode/active_sessions_try.rb
# Updated: 2025-12-06 19:02:11 -0800

require 'spec_helper'

RSpec.describe 'active_sessions_try', :full_auth_mode do
  before(:all) do
    require 'onetime'
    require 'onetime/config'
    Onetime.boot! :test
    require 'onetime/auth_config'
    require 'onetime/middleware'
    require 'onetime/application/registry'
    Onetime::Application::Registry.prepare_application_registry
    require 'rack/test'
    require 'json'
    @test = Object.new
    @test.extend Rack::Test::Methods
    def @test.app
      Onetime::Application::Registry.generate_rack_url_map
    end
    def @test.json_response
      JSON.parse(last_response.body)
    end
    def @test.create_test_account(email = "sessions-test-#{Time.now.to_i}@example.com")
      response = post '/auth/create-account',
        { login: email, password: 'Test1234!@', 'password-confirm': 'Test1234!@' }.to_json,
        { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
      # For verification, return the email
      email
    end
    def @test.login(email, password = 'Test1234!@')
      post '/auth/login',
        { login: email, password: password }.to_json,
        { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
      last_response.status == 200
    end
  end

  it 'Create test account' do
    result = begin
      @email = @test.create_test_account
      @email.include?('sessions-test')
    end
    expect(result).to eq(true)
  end

  it 'Login with test account' do
    result = begin
      @test.login(@email)
    end
    expect(result).to eq(true)
  end

  it 'Account info endpoint includes active_sessions_count' do
    result = begin
      @test.get '/auth/account', {}, { 'HTTP_ACCEPT' => 'application/json' }
      @test.last_response.status
    end
    expect(result).to eq(200)
  end

  it 'Response includes active_sessions_count field' do
    result = begin
      @account_response = @test.json_response
      @account_response.key?('active_sessions_count')
    end
    expect(result).to eq(true)
  end

  it 'Active sessions count is at least 1 (current session)' do
    result = begin
      @account_response['active_sessions_count'] >= 1
    end
    expect(result).to eq(true)
  end

  it 'GET /auth/active-sessions requires authentication' do
    result = begin
      @test.header 'Cookie', ''  # Clear cookies
      @test.get '/auth/active-sessions', {}, { 'HTTP_ACCEPT' => 'application/json' }
      @test.last_response.status
    end
    expect(result).to eq(401)
  end

  it 'Login again to test sessions list' do
    result = begin
      @test.login(@email)
    end
    expect(result).to eq(true)
  end

  it 'GET /auth/active-sessions returns 200' do
    result = begin
      @test.get '/auth/active-sessions', {}, { 'HTTP_ACCEPT' => 'application/json' }
      @test.last_response.status
    end
    expect(result).to eq(200)
  end

  it 'Response contains sessions array' do
    result = begin
      @sessions_response = @test.json_response
      @sessions_response.key?('sessions')
    end
    expect(result).to eq(true)
  end

  it 'Sessions is an array' do
    result = begin
      @sessions_response['sessions'].is_a?(Array)
    end
    expect(result).to eq(true)
  end

  it 'At least one session exists (current session)' do
    result = begin
      @sessions_response['sessions'].length >= 1
    end
    expect(result).to eq(true)
  end

  it 'Current session is marked as is_current' do
    result = begin
      @current_session = @sessions_response['sessions'].find { |s| s['is_current'] }
      @current_session.nil? == false
    end
    expect(result).to eq(true)
  end

  it 'Session has required fields' do
    result = begin
      @session = @sessions_response['sessions'].first
      @session.key?('id') && @session.key?('created_at') && @session.key?('last_activity_at')
    end
    expect(result).to eq(true)
  end

  it 'Cannot delete current session via DELETE endpoint' do
    result = begin
      @current_session_id = @sessions_response['sessions'].find { |s| s['is_current'] }['id']
      @test.delete "/auth/active-sessions/#{@current_session_id}", {}, { 'HTTP_ACCEPT' => 'application/json' }
      @test.last_response.status
    end
    expect(result).to eq(400)
  end

  it 'Error message indicates cannot remove current session' do
    result = begin
      @error_response = @test.json_response
      @error_response['error']&.include?('current session')
    end
    expect(result).to eq(true)
  end

  it 'POST /auth/remove-all-active-sessions requires authentication' do
    result = begin
      @test.header 'Cookie', ''
      @test.post '/auth/remove-all-active-sessions', {}, { 'HTTP_ACCEPT' => 'application/json' }
      @test.last_response.status
    end
    expect(result).to eq(401)
  end

  it 'Login to test removing all sessions' do
    result = begin
      @test.login(@email)
    end
    expect(result).to eq(true)
  end

  it 'POST /auth/remove-all-active-sessions returns success' do
    result = begin
      @test.post '/auth/remove-all-active-sessions', {}, { 'HTTP_ACCEPT' => 'application/json' }
      @test.last_response.status
    end
    expect(result).to eq(200)
  end

  it 'Response indicates success' do
    result = begin
      @remove_response = @test.json_response
      @remove_response.key?('success')
    end
    expect(result).to eq(true)
  end

  it 'After removing all other sessions, only current session remains' do
    result = begin
      @test.get '/auth/active-sessions', {}, { 'HTTP_ACCEPT' => 'application/json' }
      @final_sessions = @test.json_response['sessions']
      @final_sessions.length
    end
    expect(result).to eq(1)
  end

  it 'The remaining session is marked as current' do
    result = begin
      @final_sessions.first['is_current']
    end
    expect(result).to eq(true)
  end

  it 'Logout' do
    result = begin
      @test.post '/auth/logout', {}, { 'HTTP_ACCEPT' => 'application/json' }
      @test.last_response.status
    end
    expect(result).to eq(200)
  end

end
