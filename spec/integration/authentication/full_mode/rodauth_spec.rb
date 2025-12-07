# Generated rspec code for /Users/d/Projects/opensource/onetime/onetimesecret/try/integration/authentication/full_mode/rodauth_try.rb
# Updated: 2025-12-06 19:02:24 -0800

require 'spec_helper'

RSpec.describe 'rodauth_try', :full_auth_mode do
  before(:all) do
    if ENV['AUTH_DATABASE_URL'].to_s.strip.empty?
      raise RuntimeError, "Full mode requires AUTH_DATABASE_URL"
    end
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
  end

  it 'Verify full mode is active' do
    result = begin
      Onetime.auth_config.mode
    end
    expect(result).to eq('full')
  end

  it 'Verify full mode is enabled' do
    result = begin
      Onetime.auth_config.full_enabled?
    end
    expect(result).to eq(true)
  end

  it 'Verify Auth app is mounted in full mode' do
    result = begin
      Onetime::Application::Registry.mount_mappings.key?('/auth')
    end
    expect(result).to eq(true)
  end

  it 'Verify Core app is still mounted at root' do
    result = begin
      Onetime::Application::Registry.mount_mappings.key?('/')
    end
    expect(result).to eq(true)
  end

  it 'Verify mount order - Auth before Core (more specific paths first)' do
    result = begin
      paths = Onetime::Application::Registry.mount_mappings.keys
      auth_index = paths.index('/auth')
      core_index = paths.index('/')
      auth_index && core_index && auth_index < core_index
    end
    expect(result).to eq(true)
  end

  it 'Auth app responds at /auth' do
    result = begin
      @test.get '/auth'
      @test.last_response.status
    end
    expect(result).to eq(200)
  end

  it 'Auth app returns JSON' do
    result = begin
      @test.get '/auth'
      @test.last_response.headers['Content-Type']&.include?('application/json')
    end
    expect(result).to eq(true)
  end

  it 'Auth app response includes version info' do
    result = begin
      @test.get '/auth'
      response = JSON.parse(@test.last_response.body)
      response.key?('message') && response.key?('version')
    end
    expect(result).to eq(true)
  end

  it 'Health endpoint works' do
    result = begin
      @test.get '/auth/health'
      @test.last_response.status
    end
    expect(result).to eq(200)
  end

  it 'Health endpoint returns JSON' do
    result = begin
      @test.get '/auth/health'
      @test.last_response.headers['Content-Type']&.include?('application/json')
    end
    expect(result).to eq(true)
  end

  it 'Health response includes status and mode' do
    result = begin
      @test.get '/auth/health'
      health = JSON.parse(@test.last_response.body)
      health['status'] == 'ok' && health['mode'] == 'full'
    end
    expect(result).to eq(true)
  end

  it 'Admin stats endpoint exists' do
    result = begin
      @test.get '/auth/admin/stats'
      [200, 401, 403].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

  it 'Login endpoint exists' do
    result = begin
      @test.post '/auth/login',
        { login: 'test@example.com', password: 'password123' }.to_json,
        { 'CONTENT_TYPE' => 'application/json' }
      [400, 401, 422].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

  it 'Login response is JSON' do
    result = begin
      @test.post '/auth/login',
        { login: 'test@example.com', password: 'password123' }.to_json,
        { 'CONTENT_TYPE' => 'application/json' }
      @test.last_response.headers['Content-Type']&.include?('application/json')
    end
    expect(result).to eq(true)
  end

  it 'Create account endpoint exists' do
    result = begin
      @test.post '/auth/create-account',
        { login: 'new@example.com', password: 'password123' }.to_json,
        { 'CONTENT_TYPE' => 'application/json' }
      [200, 201, 400, 422].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

  it 'Create account response is JSON' do
    result = begin
      @test.post '/auth/create-account',
        { login: 'new@example.com', password: 'password123' }.to_json,
        { 'CONTENT_TYPE' => 'application/json' }
      @test.last_response.headers['Content-Type']&.include?('application/json')
    end
    expect(result).to eq(true)
  end

  it 'Core app still handles root' do
    result = begin
      @test.get '/'
      [200, 500].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

end
