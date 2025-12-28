# try/integration/api/v3/guest_routes_api_try.rb
#
# frozen_string_literal: true

#
# Integration tests for V3 API guest routes (#2190)
#
# Tests the /api/v3/guest/* endpoints with guest route gating enabled/disabled.
# These endpoints use auth=noauth strategy and are subject to guest_routes config.
#
# Routes from apps/api/v3/routes.txt:
# - /api/v3/secret/* routes use auth=sessionauth (require authentication)
# - /api/v3/guest/* routes use auth=noauth (guest accessible)
#
# Guest Routes (from routes.txt lines 19-25):
# - POST /api/v3/guest/secret/conceal
# - POST /api/v3/guest/secret/generate
# - GET  /api/v3/guest/secret/:identifier
# - POST /api/v3/guest/secret/:identifier/reveal
# - GET  /api/v3/guest/receipt/:identifier
# - POST /api/v3/guest/receipt/:identifier/burn
#
# Test Scenarios:
# 1. Guest routes return successful responses when enabled (default)
# 2. Meta/Public endpoints are always accessible

require 'rack/test'
require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry

# Create test instance with Rack::Test::Methods
@test = Object.new
@test.extend Rack::Test::Methods

def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

# Delegate Rack::Test methods to @test
def post(*args); @test.post(*args); end
def get(*args); @test.get(*args); end
def last_response; @test.last_response; end
def clear_cookies; @test.clear_cookies; end

# Setup test data
@cust = Onetime::Customer.create!(email: generate_unique_test_email("v3_guest"))
@session = { 'authenticated' => true, 'external_id' => @cust.extid, 'email' => @cust.email }

# Default guest routes config allows access
@default_config = OT.conf.dig('site', 'interface', 'api', 'guest_routes')

## Default config has guest routes enabled
[@default_config['enabled'], @default_config['conceal'], @default_config['generate']]
#=> [true, true, true]

## Guest share/conceal endpoint returns a response (not server error)
# The /api/v3/guest/* routes use auth=noauth, allowing anonymous access
# Note: Payload must be wrapped in 'secret' key per V2/V3 API contract
clear_cookies
post '/api/v3/guest/secret/conceal',
  { secret: { secret: 'test secret value', ttl: 3600 } }.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
# Should not be a server error
last_response.status < 500
#=> true

## Guest share/conceal returns 200 with valid payload
clear_cookies
post '/api/v3/guest/secret/conceal',
  { secret: { secret: 'my test secret', ttl: 3600 } }.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## Guest share/conceal response includes record.metadata structure
clear_cookies
post '/api/v3/guest/secret/conceal',
  { secret: { secret: 'test secret for metadata', ttl: 3600 } }.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
@conceal_response = JSON.parse(last_response.body)
@conceal_response.dig('record', 'metadata').is_a?(Hash)
#=> true

## Guest share/conceal metadata includes required fields
# Metadata should have key, identifier (or equivalent identifiers)
@conceal_response.dig('record', 'metadata').keys.include?('key') ||
  @conceal_response.dig('record', 'metadata').keys.include?('identifier')
#=> true

## Guest share/conceal response includes record.secret structure
@conceal_response.dig('record', 'secret').is_a?(Hash)
#=> true

## Guest share/conceal response includes details structure
@conceal_response.key?('details')
#=> true

## Guest share/generate endpoint returns a response (not server error)
clear_cookies
post '/api/v3/guest/secret/generate',
  { secret: { ttl: 3600 } }.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
# Should not be a server error
last_response.status < 500
#=> true

## Guest share/generate returns 200 with valid payload
clear_cookies
post '/api/v3/guest/secret/generate',
  { secret: { ttl: 3600 } }.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## Guest share/generate response includes record.metadata structure
@generate_response = JSON.parse(last_response.body)
@generate_response.dig('record', 'metadata').is_a?(Hash)
#=> true

## Guest share/generate response includes record.secret structure
@generate_response.dig('record', 'secret').is_a?(Hash)
#=> true

## Guest share/generate response includes details structure
@generate_response.key?('details')
#=> true

## Authenticated secret/conceal endpoint requires authentication
# The /api/v3/secret/* routes use auth=sessionauth
# Without valid session, should return 401 Unauthorized
clear_cookies
post '/api/v3/secret/conceal',
  { secret: { secret: 'test value', ttl: 3600 } }.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
# Should return 401 Unauthorized without session
last_response.status
#=> 401

## V3 status endpoint is always accessible (public meta endpoint)
clear_cookies
get '/api/v3/status',
  {},
  { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## V3 version endpoint is always accessible (public meta endpoint)
clear_cookies
get '/api/v3/version',
  {},
  { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## V3 supported-locales endpoint is always accessible (public meta endpoint)
clear_cookies
get '/api/v3/supported-locales',
  {},
  { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## V3 feedback endpoint accepts anonymous submissions
clear_cookies
post '/api/v3/feedback',
  { message: 'Test feedback', email: 'test@example.com' }.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
# Should not require authentication (auth=noauth in routes)
last_response.status < 500
#=> true

# Note: Tests for guest routes disabled behavior would require a separate test
# config file with guest_routes.enabled=false. The config is frozen at runtime
# and cannot be modified during tests. See try/integration/api/v3/guest_routes_disabled_try.rb
# for those tests (requires separate test run with modified config).

# Teardown
@cust.destroy!
