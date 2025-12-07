# Generated rspec code for /Users/d/Projects/opensource/onetime/onetimesecret/try/integration/authentication/full_mode/env_toggles/security_features_try.rb
# Updated: 2025-12-06 19:02:22 -0800

require 'spec_helper'

RSpec.describe 'security_features_try', :full_auth_mode do
  before(:all) do
    if ENV['AUTH_DATABASE_URL'].to_s.strip.empty?
      raise RuntimeError, "Full mode requires AUTH_DATABASE_URL"
    end
    ENV.delete('ENABLE_SECURITY_FEATURES')  # Ensure not set to 'false'
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

  it 'Verify security features ENV pattern (default = enabled)' do
    result = begin
      ENV['ENABLE_SECURITY_FEATURES'] != 'false'
    end
    expect(result).to eq(true)
  end

  it 'Auth app is mounted' do
    result = begin
      Onetime::Application::Registry.mount_mappings.key?('/auth')
    end
    expect(result).to eq(true)
  end

  it 'Unlock account route exists (from lockout feature)' do
    result = begin
      @test.get '/auth/unlock-account'
      [200, 400, 401, 404].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

  it 'Unlock account route response is valid (JSON or HTML redirect)' do
    result = begin
      @test.get '/auth/unlock-account'
      content_type = @test.last_response.headers['Content-Type']
      is_json = content_type&.include?('application/json')
      is_html = content_type&.include?('text/html')
      is_valid_status = [200, 302, 400, 401, 404].include?(@test.last_response.status)
      (is_json || is_html) && is_valid_status
    end
    expect(result).to eq(true)
  end

  it 'Login endpoint still works with security features enabled' do
    result = begin
      @test.post '/auth/login',
        { login: 'test@example.com', password: 'wrongpassword' }.to_json,
        { 'CONTENT_TYPE' => 'application/json' }
      [400, 401, 422].include?(@test.last_response.status)
    end
    expect(result).to eq(true)
  end

  it 'Auth::Config has lockout feature methods' do
    result = begin
      Auth::Config.method_defined?(:max_invalid_logins) || Auth::Config.private_method_defined?(:max_invalid_logins)
    end
    expect(result).to eq(true)
  end

  it 'Auth::Config has active_sessions feature methods' do
    result = begin
      Auth::Config.method_defined?(:session_inactivity_deadline) || Auth::Config.private_method_defined?(:session_inactivity_deadline)
    end
    expect(result).to eq(true)
  end

end
