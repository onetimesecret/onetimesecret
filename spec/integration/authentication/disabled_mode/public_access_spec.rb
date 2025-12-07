# Generated rspec code for /Users/d/Projects/opensource/onetime/onetimesecret/try/integration/authentication/disabled_mode/public_access_try.rb
# Updated: 2025-12-06 19:02:10 -0800

require 'spec_helper'

RSpec.describe 'public_access_try' do
  before(:all) do
    skip "Requires AUTHENTICATION_MODE=disabled" unless ENV['AUTHENTICATION_MODE'] == 'disabled'
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
  end

  it 'Verify disabled mode is active' do
    result = begin
      ENV['AUTHENTICATION_MODE']
    end
    expect(result).to eq('disabled')
  end

  it 'Auth app should NOT be mounted in disabled mode' do
    result = begin
      Onetime::Application::Registry.mount_mappings.key?('/auth')
    end
    expect(result).to eq(false)
  end

  it 'Core app is still mounted at root' do
    result = begin
      Onetime::Application::Registry.mount_mappings.key?('/')
    end
    expect(result).to eq(true)
  end

  it 'Login endpoint redirects in disabled mode' do
    result = begin
      @test.post '/auth/login', { login: 'test@example.com', password: 'password' }
      @test.last_response.status
    end
    expect(result).to eq(302)
  end

  it 'Signup endpoint redirects in disabled mode' do
    result = begin
      @test.post '/auth/create-account', { login: 'new@example.com', password: 'password' }
      @test.last_response.status
    end
    expect(result).to eq(302)
  end

  it 'Logout endpoint redirects in disabled mode' do
    result = begin
      @test.post '/auth/logout'
      @test.last_response.status
    end
    expect(result).to eq(302)
  end

  it 'Reset password endpoint redirects in disabled mode' do
    result = begin
      @test.post '/auth/reset-password', { login: 'test@example.com' }
      @test.last_response.status
    end
    expect(result).to eq(302)
  end

  it 'Sign-in page still exists in disabled mode' do
    result = begin
      @test.get '/signin'
      @test.last_response.status
    end
    expect(result).to eq(200)
  end

  it 'Sign-up page still exists in disabled mode' do
    result = begin
      @test.get '/signup'
      @test.last_response.status
    end
    expect(result).to eq(200)
  end

  it 'API status endpoint is accessible without auth' do
    result = begin
      @test.get '/api/v2/status'
      @test.last_response.status
    end
    expect(result).to eq(200)
  end

  it 'Creating secrets fails without proper parameters' do
    result = begin
      @test.post '/api/v2/secret',
        { secret: 'test-secret', ttl: 300 }.to_json,
        { 'CONTENT_TYPE' => 'application/json' }
      @test.last_response.status
    end
    expect(result).to eq(404)
  end

  it 'Protected endpoints are accessible (no protection)' do
    result = begin
      @test.get '/dashboard'
      [200, 302, 404].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

  it 'Homepage is accessible without authentication' do
    result = begin
      @test.get '/'
      @test.last_response.status
    end
    expect(result).to eq(200)
  end

  it 'No session cookie is set in disabled mode' do
    result = begin
      @test.get '/'
      @test.last_response['Set-Cookie']
    end
    expect(result).to eq(nil)
  end

  after(:all) do
    @test = nil
  end
end
