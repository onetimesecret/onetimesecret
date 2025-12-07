# Generated rspec code for /Users/d/Projects/opensource/onetime/onetimesecret/try/integration/authentication/full_mode/env_toggles/magic_links_enabled_try.rb
# Updated: 2025-12-06 19:02:21 -0800

require 'spec_helper'

RSpec.describe 'magic_links_enabled_try', :full_auth_mode do
  before(:all) do
    if ENV['AUTH_DATABASE_URL'].to_s.strip.empty?
      raise RuntimeError, "Full mode requires AUTH_DATABASE_URL"
    end
    ENV['ENABLE_MAGIC_LINKS'] = 'true'
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
    rescue JSON::ParserError
      {}
    end
  end

  it 'Verify magic links ENV is set correctly' do
    result = begin
      ENV['ENABLE_MAGIC_LINKS']
    end
    expect(result).to eq('true')
  end

  it 'Verify magic links ENV pattern evaluates to enabled' do
    result = begin
      ENV['ENABLE_MAGIC_LINKS'] == 'true'
    end
    expect(result).to eq(true)
  end

  it 'Auth app is mounted' do
    result = begin
      Onetime::Application::Registry.mount_mappings.key?('/auth')
    end
    expect(result).to eq(true)
  end

  it 'Auth::Config has email_auth feature methods' do
    result = begin
      Auth::Config.method_defined?(:email_auth_route) || Auth::Config.private_method_defined?(:email_auth_route)
    end
    expect(result).to eq(true)
  end

  it 'Auth::Config has create_email_auth_key method' do
    result = begin
      Auth::Config.method_defined?(:create_email_auth_key) || Auth::Config.private_method_defined?(:create_email_auth_key)
    end
    expect(result).to eq(true)
  end

  it 'Email login request route exists (POST to request magic link)' do
    result = begin
      @test.post '/auth/email-login-request',
        { login: 'test@example.com' }.to_json,
        { 'CONTENT_TYPE' => 'application/json' }
      [200, 400, 401, 422].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

  it 'Email login request route returns JSON' do
    result = begin
      @test.post '/auth/email-login-request',
        { login: 'test@example.com' }.to_json,
        { 'CONTENT_TYPE' => 'application/json' }
      @test.last_response.headers['Content-Type']&.include?('application/json')
    end
    expect(result).to eq(true)
  end

  it 'Email login route exists (GET to verify token)' do
    result = begin
      @test.get '/auth/email-login'
      [200, 400, 401, 422].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

  it 'Email login route with invalid token returns error' do
    result = begin
      @test.get '/auth/email-login?key=invalid_token_12345'
      [400, 401, 422].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

  it 'Standard login still works with magic links enabled' do
    result = begin
      @test.post '/auth/login',
        { login: 'test@example.com', password: 'wrongpassword' }.to_json,
        { 'CONTENT_TYPE' => 'application/json' }
      [400, 401, 422].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

end
