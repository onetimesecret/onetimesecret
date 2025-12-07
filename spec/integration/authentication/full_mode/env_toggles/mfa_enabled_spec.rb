# Generated rspec code for /Users/d/Projects/opensource/onetime/onetimesecret/try/integration/authentication/full_mode/env_toggles/mfa_enabled_try.rb
# Updated: 2025-12-06 19:02:22 -0800

require 'spec_helper'

RSpec.describe 'mfa_enabled_try', :full_auth_mode do
  before(:all) do
    if ENV['AUTH_DATABASE_URL'].to_s.strip.empty?
      raise RuntimeError, "Full mode requires AUTH_DATABASE_URL"
    end
    ENV['ENABLE_MFA'] = 'true'
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

  it 'Verify MFA ENV is set correctly' do
    result = begin
      ENV['ENABLE_MFA']
    end
    expect(result).to eq('true')
  end

  it 'Verify MFA ENV pattern evaluates to enabled' do
    result = begin
      ENV['ENABLE_MFA'] == 'true'
    end
    expect(result).to eq(true)
  end

  it 'Auth app is mounted' do
    result = begin
      Onetime::Application::Registry.mount_mappings.key?('/auth')
    end
    expect(result).to eq(true)
  end

  it 'Auth::Config has OTP feature methods' do
    result = begin
      Auth::Config.method_defined?(:otp_setup_route) || Auth::Config.private_method_defined?(:otp_setup_route)
    end
    expect(result).to eq(true)
  end

  it 'Auth::Config has recovery codes feature methods' do
    result = begin
      Auth::Config.method_defined?(:recovery_codes_route) || Auth::Config.private_method_defined?(:recovery_codes_route)
    end
    expect(result).to eq(true)
  end

  it 'Auth::Config has two_factor_base feature methods' do
    result = begin
      Auth::Config.method_defined?(:two_factor_authentication_setup?) || Auth::Config.private_method_defined?(:two_factor_authentication_setup?)
    end
    expect(result).to eq(true)
  end

  it 'OTP setup route exists (may redirect or return auth error)' do
    result = begin
      @test.get '/auth/otp-setup'
      [200, 302, 401, 403].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

  it 'OTP setup route response is valid' do
    result = begin
      @test.get '/auth/otp-setup'
      content_type = @test.last_response.headers['Content-Type']
      is_json = content_type&.include?('application/json')
      is_html = content_type&.include?('text/html')
      is_redirect = @test.last_response.status == 302
      is_json || is_html || is_redirect
    end
    expect(result).to eq(true)
  end

  it 'OTP auth route exists' do
    result = begin
      @test.post '/auth/otp-auth',
        { otp_code: '123456' }.to_json,
        { 'CONTENT_TYPE' => 'application/json' }
      [200, 400, 401, 403, 422].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

  it 'Recovery codes route exists (may redirect or return auth error)' do
    result = begin
      @test.get '/auth/recovery-codes'
      [200, 302, 401, 403].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

  it 'Recovery auth route exists' do
    result = begin
      @test.post '/auth/recovery-auth',
        { recovery_code: 'abc12345' }.to_json,
        { 'CONTENT_TYPE' => 'application/json' }
      [200, 400, 401, 403, 422].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

  it 'Login still works with MFA enabled' do
    result = begin
      @test.post '/auth/login',
        { login: 'test@example.com', password: 'wrongpassword' }.to_json,
        { 'CONTENT_TYPE' => 'application/json' }
      [400, 401, 422].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

end
