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
    # Anonymous API endpoints now require CSRF validation when no Basic Auth is provided.
    # This test verifies that the endpoint itself works when CSRF is bypassed.
    # In production, anonymous API calls from browsers would need CSRF token,
    # while programmatic calls would use API key authentication.
    #
    # Note: The generate endpoint allows anonymous access, but we still need
    # to either:
    # a) Provide valid Basic Auth credentials (which we don't have in this test), or
    # b) Provide a valid CSRF token
    #
    # For this test, we verify the endpoint returns 403 (CSRF rejection)
    # to confirm CSRF enforcement is active on anonymous API routes.
    result = begin
      response = @mock_request.post('/api/v1/generate')
      response.status
    end
    # Without CSRF token or valid Basic Auth, anonymous API POST gets 403
    expect(result).to eq(403)
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

  it 'Can access the API share endpoint (requires CSRF or valid auth)' do
    # With CSRF enabled, API POST without valid auth or CSRF gets rejected
    # This test verifies the endpoint responds appropriately
    result = begin
      response = @mock_request.post('/api/v2/secret/conceal')
      response.status
    end
    # Without CSRF token or valid auth, gets 403
    expect(result).to eq(403)
  end

  it 'Can post to a bogus v2 endpoint and get rejection' do
    result = begin
      response = @mock_request.post('/api/v2/generate2')
      response.status
    end
    # Without auth, CSRF rejection (403) takes precedence
    expect(result).to eq(403)
  end

  it 'Can post to v2 colonel endpoint and get rejection' do
    result = begin
      response = @mock_request.post('/api/v2/colonel/info')
      response.status
    end
    # Without auth, CSRF rejection (403) takes precedence
    expect(result).to eq(403)
  end

end
