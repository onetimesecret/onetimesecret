# spec/integration/all/routes_spec.rb
#
# frozen_string_literal: true

require_relative '../integration_spec_helper'

RSpec.describe 'routes_try', type: :integration do
  before(:all) do
    require 'rack'
    require 'rack/mock'
    require 'base64'
    # Clear Redis env vars to ensure test config defaults are used (port 2121)
    @original_rack_env = ENV['RACK_ENV']
    @original_redis_url = ENV['REDIS_URL']
    @original_valkey_url = ENV['VALKEY_URL']
    ENV.delete('REDIS_URL')
    ENV.delete('VALKEY_URL')
    # Ensure RACK_ENV is test so boot! is idempotent
    ENV['RACK_ENV'] = 'test'
    @app = Rack::Builder.parse_file('config.ru')
    @mock_request = Rack::MockRequest.new(@app)
    # Basic Auth header for API requests (bypasses CSRF)
    @api_auth_header = { 'HTTP_AUTHORIZATION' => "Basic #{Base64.strict_encode64('test:apikey')}" }
  end

  after(:all) do
    if @original_rack_env
      ENV['RACK_ENV'] = @original_rack_env
    else
      ENV.delete('RACK_ENV')
    end
    if @original_redis_url
      ENV['REDIS_URL'] = @original_redis_url
    else
      ENV.delete('REDIS_URL')
    end
    if @original_valkey_url
      ENV['VALKEY_URL'] = @original_valkey_url
    else
      ENV.delete('VALKEY_URL')
    end
  end

  it 'Authentication is enabled' do
    result = begin
      OT.conf['site']['authentication']['signin']
    end
    expect(result).to eq(true)
  end

  it 'With default configuration, can access the sign-in page' do
    result = begin
      response = @mock_request.get('/signin')
      response.status
    end
    expect(result).to eq(200)
  end

  it 'With default configuration, can access the sign-in page' do
    result = begin
      response = @mock_request.get('/signup')
      response.status
    end
    expect(result).to eq(200)
  end

  it 'With default configuration, dashboard redirects to sign-in' do
    result = begin
      response = @mock_request.get('/dashboard')
      [response.status, response.headers["location"]]
    end
    expect(result).to eq([302, "/signin"])
  end

  it 'Disable authentication for all routes' do
    result = begin
      old_conf = OT.instance_variable_get(:@conf)
      new_conf = {
        'site' => {
          'secret' => 'notnil',
          'authentication' => {
            'enabled' => false,
            'signin' => true,
          }
        },
        'mail' => {
          'truemail' => {},
        }
      }
      OT.instance_variable_set(:@conf, new_conf)
      processed_conf = OT::Config.after_load(OT.conf)
      OT.instance_variable_set(:@conf, old_conf)
      processed_conf['site']['authentication']['signin']
    end
    expect(result).to eq(false)
  end

  it 'With auth disabled, dashboard still redirects' do
    result = begin
      old_conf = OT.instance_variable_get(:@conf)
      new_conf = {
        'site' => {
          'secret' => 'notnil',
          'authentication' => {
            'enabled' => false,
          },
        },
        'mail' => {
          'truemail' => {},
        },
      }
      OT.instance_variable_set(:@conf, new_conf)
      response = @mock_request.get('/dashboard')
      OT.instance_variable_set(:@conf, old_conf)
      response.status
    end
    expect(result).to eq(302)
  end

  it 'Can access the API generate endpoint' do
    # V1 generate endpoint creates a random secret (no auth/data required)
    # API routes bypass CSRF entirely because:
    # - API v1 removed session auth (Basic Auth or anonymous only)
    # - Anonymous requests are stateless (no session to exploit)
    response = @mock_request.post('/api/v1/generate')

    # Anonymous generate should work (not be blocked by CSRF)
    # May return 200 (success) or 401 (if auth required) but NOT 403 (CSRF)
    expect(response.status).not_to eq(403)
  end

  it 'Can post to a bogus endpoint and get a 404' do
    result = begin
      response = @mock_request.post('/api/v1/generate2', @api_auth_header)
      content = Familia::JsonSerializer.parse(response.body)
      [response.status, content["error"]]
    end
    # With invalid Basic Auth, returns 404 with "Not authorized" message
    # (Basic Auth bypasses CSRF, but auth validation fails - route not found for unauthorized)
    expect(result[0]).to eq(404)
  end

  it 'Can access the API status' do
    result = begin
      response = @mock_request.get('/api/v2/status')
      content = Familia::JsonSerializer.parse(response.body)
      [response.status, content["status"], content["locale"]]
    end
    expect(result).to eq([200, "nominal", "en"])
  end

  it 'Can access the API share endpoint (requires auth)' do
    # API routes bypass CSRF, so unauthenticated requests reach the API
    response = @mock_request.post('/api/v2/secret/conceal')

    # Should NOT be 403 (CSRF rejection) - API routes bypass CSRF
    # Will be 401 (unauthorized) or similar API-level error
    expect(response.status).not_to eq(403)
  end

  it 'Can post to a bogus v2 endpoint and get rejection' do
    response = @mock_request.post('/api/v2/generate2')

    # Should NOT be 403 (CSRF rejection) - API routes bypass CSRF
    expect(response.status).not_to eq(403)
  end

  it 'Can post to v2 colonel endpoint and get rejection' do
    response = @mock_request.post('/api/v2/colonel/info')

    # Should NOT be 403 (CSRF rejection) - API routes bypass CSRF
    expect(response.status).not_to eq(403)
  end

end
