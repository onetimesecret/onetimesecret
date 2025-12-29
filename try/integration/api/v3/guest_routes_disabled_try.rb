# try/integration/api/v3/guest_routes_disabled_try.rb
#
# frozen_string_literal: true

#
# Integration tests for V3 API guest routes when DISABLED (#2190)
#
# Tests the HTTP-level behavior when guest routes are disabled via config.
# These tests temporarily override the config to simulate disabled states.
#
# Test Scenarios:
# 1. Global guest_routes.enabled=false returns 403 with error code
# 2. Individual operation disabled returns 403 with operation-specific code
# 3. Error response contains proper JSON structure
# 4. Authenticated endpoints still work when guest routes disabled
# 5. Meta/public endpoints unaffected by guest route config

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

# Helper to temporarily override guest routes config
# Uses OT.instance_variable_set to swap config during test
def with_guest_routes_config(config_overrides)
  original_conf = OT.conf

  # Create a mutable copy of the config
  test_conf = Onetime::Config.deep_clone(original_conf)

  # Apply overrides to guest_routes
  test_conf['site'] ||= {}
  test_conf['site']['interface'] ||= {}
  test_conf['site']['interface']['api'] ||= {}
  test_conf['site']['interface']['api']['guest_routes'] = config_overrides

  # Temporarily replace config
  OT.instance_variable_set(:@conf, test_conf)

  yield
ensure
  OT.instance_variable_set(:@conf, original_conf)
end

# JSON request helper
def json_headers
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
end

# Setup test data
@cust = Onetime::Customer.create!(email: generate_unique_test_email("v3_guest_disabled"))

# GLOBAL GUEST ROUTES DISABLED TESTS

## Guest conceal returns 403 when guest_routes.enabled=false
with_guest_routes_config({ 'enabled' => false }) do
  clear_cookies
  post '/api/v3/guest/secret/conceal',
    { secret: { secret: 'test secret', ttl: 3600 } }.to_json,
    json_headers
  last_response.status
end
#=> 403

## 403 response includes GUEST_ROUTES_DISABLED code in body
with_guest_routes_config({ 'enabled' => false }) do
  clear_cookies
  post '/api/v3/guest/secret/conceal',
    { secret: { secret: 'test secret', ttl: 3600 } }.to_json,
    json_headers
  body = JSON.parse(last_response.body)
  body['code']
end
#=> "GUEST_ROUTES_DISABLED"

## 403 response includes user-friendly message
with_guest_routes_config({ 'enabled' => false }) do
  clear_cookies
  post '/api/v3/guest/secret/conceal',
    { secret: { secret: 'test secret', ttl: 3600 } }.to_json,
    json_headers
  body = JSON.parse(last_response.body)
  body['message']
end
#=> "Guest API access is disabled"

## Guest generate returns 403 when guest_routes.enabled=false
with_guest_routes_config({ 'enabled' => false }) do
  clear_cookies
  post '/api/v3/guest/secret/generate',
    { secret: { ttl: 3600 } }.to_json,
    json_headers
  last_response.status
end
#=> 403

# INDIVIDUAL OPERATION DISABLED TESTS

## Guest conceal returns 403 when conceal specifically disabled
with_guest_routes_config({ 'enabled' => true, 'conceal' => false }) do
  clear_cookies
  post '/api/v3/guest/secret/conceal',
    { secret: { secret: 'test secret', ttl: 3600 } }.to_json,
    json_headers
  last_response.status
end
#=> 403

## Operation-specific 403 includes GUEST_CONCEAL_DISABLED code
with_guest_routes_config({ 'enabled' => true, 'conceal' => false }) do
  clear_cookies
  post '/api/v3/guest/secret/conceal',
    { secret: { secret: 'test secret', ttl: 3600 } }.to_json,
    json_headers
  body = JSON.parse(last_response.body)
  body['code']
end
#=> "GUEST_CONCEAL_DISABLED"

## Operation-specific 403 message is descriptive
with_guest_routes_config({ 'enabled' => true, 'conceal' => false }) do
  clear_cookies
  post '/api/v3/guest/secret/conceal',
    { secret: { secret: 'test secret', ttl: 3600 } }.to_json,
    json_headers
  body = JSON.parse(last_response.body)
  body['message']
end
#=> "Guest conceal is disabled"

## Guest generate returns 403 when generate specifically disabled
with_guest_routes_config({ 'enabled' => true, 'generate' => false }) do
  clear_cookies
  post '/api/v3/guest/secret/generate',
    { secret: { ttl: 3600 } }.to_json,
    json_headers
  last_response.status
end
#=> 403

## Generate disabled returns GUEST_GENERATE_DISABLED code
with_guest_routes_config({ 'enabled' => true, 'generate' => false }) do
  clear_cookies
  post '/api/v3/guest/secret/generate',
    { secret: { ttl: 3600 } }.to_json,
    json_headers
  body = JSON.parse(last_response.body)
  body['code']
end
#=> "GUEST_GENERATE_DISABLED"

# MIXED CONFIG TESTS

## Conceal works when only generate is disabled
with_guest_routes_config({ 'enabled' => true, 'conceal' => true, 'generate' => false }) do
  clear_cookies
  post '/api/v3/guest/secret/conceal',
    { secret: { secret: 'this should work', ttl: 3600 } }.to_json,
    json_headers
  last_response.status
end
#=> 200

## Generate fails when only generate is disabled (conceal enabled)
with_guest_routes_config({ 'enabled' => true, 'conceal' => true, 'generate' => false }) do
  clear_cookies
  post '/api/v3/guest/secret/generate',
    { secret: { ttl: 3600 } }.to_json,
    json_headers
  last_response.status
end
#=> 403

# META/PUBLIC ENDPOINTS UNAFFECTED

## Status endpoint works even when guest routes globally disabled
with_guest_routes_config({ 'enabled' => false }) do
  clear_cookies
  get '/api/v3/status', {}, { 'HTTP_ACCEPT' => 'application/json' }
  last_response.status
end
#=> 200

## Version endpoint works even when guest routes globally disabled
with_guest_routes_config({ 'enabled' => false }) do
  clear_cookies
  get '/api/v3/version', {}, { 'HTTP_ACCEPT' => 'application/json' }
  last_response.status
end
#=> 200

## Supported-locales endpoint works even when guest routes globally disabled
with_guest_routes_config({ 'enabled' => false }) do
  clear_cookies
  get '/api/v3/supported-locales', {}, { 'HTTP_ACCEPT' => 'application/json' }
  last_response.status
end
#=> 200

# RESPONSE STRUCTURE VALIDATION

## 403 response has valid JSON content-type
with_guest_routes_config({ 'enabled' => false }) do
  clear_cookies
  post '/api/v3/guest/secret/conceal',
    { secret: { secret: 'test', ttl: 3600 } }.to_json,
    json_headers
  last_response.content_type.include?('application/json')
end
#=> true

## 403 response body is valid JSON with expected keys
with_guest_routes_config({ 'enabled' => false }) do
  clear_cookies
  post '/api/v3/guest/secret/conceal',
    { secret: { secret: 'test', ttl: 3600 } }.to_json,
    json_headers
  body = JSON.parse(last_response.body)
  body.keys.sort
end
#=> ["code", "message"]

# Teardown
@cust.destroy!
