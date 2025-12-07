# Generated rspec code for /Users/d/Projects/opensource/onetime/onetimesecret/try/integration/authentication/simple_mode/core_auth_try.rb
# Updated: 2025-12-06 19:02:32 -0800

require 'spec_helper'

RSpec.describe 'core_auth_try', :simple_auth_mode do
  before(:all) do
    require 'onetime'
    require 'onetime/config'
    Onetime.boot! :test
    require 'onetime/auth_config'
    require 'onetime/middleware'
    require 'onetime/application/registry'
    Onetime::Application::Registry.reset!
    Onetime::Application::Registry.prepare_application_registry
    require 'rack/test'
    require 'json'
    @test = Object.new
    @test.extend Rack::Test::Methods
    def @test.app
      core_app_class = Onetime::Application::Registry.mount_mappings['/']
      core_app_class.new
    end
    def @test.json_body
      JSON.parse(last_response.body)
    end
    def @test.json_response?
      # Try both common variations of content-type header
      content_type = last_response.headers['content-type'] || last_response.headers['Content-Type']
      # Rack::MockResponse
      content_type&.include?('application/json')
    end
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

  it 'Verify Auth app is not mounted in simple mode' do
    result = begin
      p [:PLOP, Onetime::Application::Registry.mount_mappings]
      Onetime::Application::Registry.mount_mappings.key?('/auth')
    end
    expect(result).to eq(false)
  end

  it 'Verify Core app is mounted at root' do
    result = begin
      Onetime::Application::Registry.mount_mappings.key?('/')
    end
    expect(result).to eq(true)
  end

  it 'Login with JSON request - invalid credentials returns 401' do
    result = begin
      @test.post '/auth/login',
        { login: 'nonexistent@example.com', password: 'wrongpassword' }.to_json,
        { 'HTTP_ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }
      @test.last_response.status
    end
    expect(result).to eq(401)
  end

  it 'Login error returns JSON format' do
    result = begin
      @test.json_response?
    end
    expect(result).to eq(true)
  end

  it 'Login error response body is not empty' do
    result = begin
      @test.last_response.body.length > 0
    end
    expect(result).to eq(true)
  end

  it 'Parse JSON response and verify structure' do
    result = begin
      begin
        response = @test.json_body
        has_error = response.key?('error')
        has_field_error = response.key?('field-error')
        field_error_valid = has_field_error && response['field-error'].is_a?(Array) && response['field-error'].length == 2
        # Combine all checks
        has_error && has_field_error && field_error_valid &&
          response['field-error'][0] == 'email' &&
          response['field-error'][1] == 'invalid'
      rescue => e
        puts "JSON parse or validation error: #{e.message}"
        puts "Response body: #{@test.last_response.body}" if @test.last_response
        false
      end
    end
    expect(result).to eq(true)
  end

  it 'Create account with JSON request - missing parameters' do
    result = begin
      @test.post '/auth/create-account',
        { login: 'incomplete@example.com' }.to_json,
        { 'HTTP_ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }
      [400, 401, 422].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

  it 'Response is JSON' do
    result = begin
      @test.json_response?
    end
    expect(result).to eq(true)
  end

  it 'Logout with JSON request - no active session' do
    result = begin
      @test.post '/auth/logout',
        {}.to_json,
        { 'HTTP_ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }
      [200, 302].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

  it 'If JSON requested and successful, response is JSON' do
    result = begin
      if @test.last_response.status == 200
        @test.json_response?
      else
        true  # Skip check if redirected (means JSON detection failed)
      end
    end
    expect(result).to eq(true)
  end

  it 'Request password reset with JSON' do
    result = begin
      @test.post '/auth/reset-password',
        { login: 'reset@example.com' }.to_json,
        { 'HTTP_ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }
      [200, 400, 422].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

  it 'Response is JSON' do
    result = begin
      @test.json_response?
    end
    expect(result).to eq(true)
  end

  it 'Reset password with token and JSON request' do
    result = begin
      @test.post '/auth/reset-password/testtoken123',
        { newpassword: 'newpassword123', 'password-confirm': 'newpassword123' }.to_json,
        { 'HTTP_ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }
      [400, 404, 422].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

  it 'Response is JSON' do
    result = begin
      @test.json_response?
    end
    expect(result).to eq(true)
  end

  it 'POST without JSON Accept header redirects or returns HTML' do
    result = begin
      @test.post '/auth/login',
        { login: 'test@example.com', password: 'password' }
      [302, 401, 500].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

  it 'Response without JSON Accept is not JSON' do
    result = begin
      @test.json_response?
    end
    expect(result).to eq(false)
  end

  after(:all) do
    @test = nil
  end
end
