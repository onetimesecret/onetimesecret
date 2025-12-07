# Generated rspec code for /Users/d/Projects/opensource/onetime/onetimesecret/try/integration/authentication/simple_mode/adapter_try.rb
# Updated: 2025-12-06 19:02:31 -0800

require 'spec_helper'

RSpec.describe 'adapter_try', :simple_auth_mode do
  before(:all) do
    require 'onetime'
    require 'onetime/config'
    Onetime.boot! :cli
    require 'onetime/auth_config'
    require 'onetime/middleware'
    require 'web/auth/application'
    require 'rack/test'
    @test = Object.new
    @test.extend Rack::Test::Methods
    def @test.app
      Auth::Application.new
    end
  end

  it 'Verify the auth application starts in simple mode without database errors' do
    result = begin
      begin
        app = Auth::Application.new
        app.respond_to?(:call)
      rescue => e
        e
      end
    end
    expect(result).to eq(true)
  end

  it 'Verify simple mode is active' do
    result = begin
      Onetime.auth_config.mode
    end
    expect(result).to eq('simple')
  end

  it 'Verify full mode is disabled' do
    result = begin
      Onetime.auth_config.full_enabled?
    end
    expect(result).to eq(false)
  end

  it 'Verify database connection returns nil in simple mode' do
    result = begin
      require 'web/auth/config/database'
      Auth::Database.connection
    end
    expect(result).to eq(nil)
  end

  it 'The login endpoint returns 404 in simple mode (Rodauth not loaded)' do
    result = begin
      @test.post '/auth/login', { login: 'test@example.com', password: 'password' }
      @test.last_response.status
    end
    expect(result).to eq(404)
  end

  it 'Check that we're getting an error response' do
    result = begin
      @test.last_response.body.length > 0
    end
    expect(result).to eq(true)
  end

  it 'Verify JSON response when Accept header is set for login' do
    result = begin
      @test.post '/auth/login',
        { login: 'test@example.com', password: 'invalid' },
        { 'HTTP_ACCEPT' => 'application/json' }
      content_type = @test.last_response.headers['Content-Type']
      content_type && content_type.include?('application/json')
    end
    expect(result).to eq(true)
  end

  it 'The create account endpoint returns 404 in simple mode' do
    result = begin
      @test.post '/auth/create-account', { login: 'new@example.com', password: 'password' }
      @test.last_response.status
    end
    expect(result).to eq(404)
  end

  it 'The password reset endpoint returns 404 in simple mode' do
    result = begin
      @test.post '/auth/reset-password', { login: 'reset@example.com' }
      @test.last_response.status
    end
    expect(result).to eq(404)
  end

  it 'The reset password with token endpoint returns 404 in simple mode' do
    result = begin
      @test.post '/auth/reset-password/testkey123', { p: 'newpassword' }
      @test.last_response.status
    end
    expect(result).to eq(404)
  end

  it 'The logout endpoint should be accessible (forwarding works)' do
    result = begin
      @test.post '/auth/logout'
      [404, 500].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

  it 'Verify Core app can be accessed through Registry' do
    result = begin
      if Onetime::Application::Registry.mount_mappings.empty?
        Onetime::Application::Registry.prepare_application_registry
      end
      core_app_class = Onetime::Application::Registry.mount_mappings['/']
      !core_app_class.nil?
    end
    expect(result).to eq(true)
  end

  it 'Verify Core app can be instantiated' do
    result = begin
      core_app_class = Onetime::Application::Registry.mount_mappings['/']
      core_app = core_app_class.new
      core_app.is_a?(Core::Application)
    end
    expect(result).to eq(true)
  end

  after(:all) do
    @test = nil
  end
end
