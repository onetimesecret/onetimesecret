# try/features/incoming/91_incoming_routes_try.rb
#
# frozen_string_literal: true

# Rack-level HTTP integration tests for V3 incoming routes.
# Tests the following endpoints via Rack::MockRequest:
# - GET  /api/v3/incoming/config
# - POST /api/v3/incoming/validate
# - POST /api/v3/incoming/secret
#
# All incoming routes use auth=noauth and are accessible to anonymous callers.
# Tests cover both the disabled (default) and enabled feature paths.

require 'rack/test'
require 'digest'
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

# Store original config for restoration
@original_conf = YAML.load(YAML.dump(OT.conf))

# Recipient config for enabled tests
@test_recipient_email = "incoming-routes+#{Familia.now.to_i}@onetimesecret.com"
@test_recipient_hash  = nil # set after enable_incoming

# Helper to enable incoming feature with a test recipient
def enable_incoming_for_routes(recipient_email)
  new_conf = YAML.load(YAML.dump(OT.conf))
  new_conf['features']['incoming']['enabled'] = true
  OT.send(:conf=, new_conf)

  # Compute hash using the same method as setup_incoming_recipients
  site_secret = OT.conf.dig('site', 'secret') || 'test-secret'
  hash_key = Digest::SHA256.hexdigest("#{recipient_email}:#{site_secret}")[0..15]

  OT.instance_variable_set(:@incoming_recipient_lookup, {
    hash_key => recipient_email
  }.freeze)
  OT.instance_variable_set(:@incoming_public_recipients, [
    { hash: hash_key, name: 'Test Recipient' }
  ].freeze)

  hash_key
end

def disable_incoming_for_routes(original_conf)
  OT.send(:conf=, original_conf)
  OT.instance_variable_set(:@incoming_recipient_lookup, {}.freeze)
  OT.instance_variable_set(:@incoming_public_recipients, [].freeze)
end

# --- Tests with feature disabled (default) ---

## GET /api/v3/incoming/config returns 200 even when feature is disabled
clear_cookies
get '/api/v3/incoming/config', {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## GET /api/v3/incoming/config response includes config key when disabled
clear_cookies
get '/api/v3/incoming/config', {}, { 'HTTP_ACCEPT' => 'application/json' }
body = JSON.parse(last_response.body)
body.key?('config')
#=> true

## GET /api/v3/incoming/config reports enabled:false when feature is disabled
clear_cookies
get '/api/v3/incoming/config', {}, { 'HTTP_ACCEPT' => 'application/json' }
body = JSON.parse(last_response.body)
body.dig('config', 'enabled')
#=> false

## POST /api/v3/incoming/validate returns non-5xx when feature disabled
clear_cookies
post '/api/v3/incoming/validate',
  { recipient: 'anyhash' }.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status < 500
#=> true

## POST /api/v3/incoming/secret returns non-5xx when feature disabled
clear_cookies
post '/api/v3/incoming/secret',
  { secret: { secret: 'content', recipient: 'hash', memo: '' } }.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status < 500
#=> true

# --- Tests with feature enabled ---

## GET /api/v3/incoming/config returns 200 with enabled:true when feature is on
@test_recipient_hash = enable_incoming_for_routes(@test_recipient_email)
clear_cookies
get '/api/v3/incoming/config', {}, { 'HTTP_ACCEPT' => 'application/json' }
body = JSON.parse(last_response.body)
body.dig('config', 'enabled')
#=> true

## GET /api/v3/incoming/config includes recipients array with hash and name (no email)
@test_recipient_hash = enable_incoming_for_routes(@test_recipient_email)
clear_cookies
get '/api/v3/incoming/config', {}, { 'HTTP_ACCEPT' => 'application/json' }
body = JSON.parse(last_response.body)
recipients = body.dig('config', 'recipients')
recipients.is_a?(Array) && !recipients.empty?
#=> true

## GET /api/v3/incoming/config recipients have hash and name keys
@test_recipient_hash = enable_incoming_for_routes(@test_recipient_email)
clear_cookies
get '/api/v3/incoming/config', {}, { 'HTTP_ACCEPT' => 'application/json' }
body = JSON.parse(last_response.body)
first = body.dig('config', 'recipients', 0)
first.key?('hash') && first.key?('name')
#=> true

## GET /api/v3/incoming/config recipients do not expose email addresses
@test_recipient_hash = enable_incoming_for_routes(@test_recipient_email)
clear_cookies
get '/api/v3/incoming/config', {}, { 'HTTP_ACCEPT' => 'application/json' }
body = JSON.parse(last_response.body)
first = body.dig('config', 'recipients', 0)
# Should not contain email — only hash and name
!first.key?('email')
#=> true

## GET /api/v3/incoming/config includes memo_max_length
@test_recipient_hash = enable_incoming_for_routes(@test_recipient_email)
clear_cookies
get '/api/v3/incoming/config', {}, { 'HTTP_ACCEPT' => 'application/json' }
body = JSON.parse(last_response.body)
body.dig('config', 'memo_max_length').is_a?(Integer)
#=> true

## POST /api/v3/incoming/validate returns 200 with valid:true for known hash
@test_recipient_hash = enable_incoming_for_routes(@test_recipient_email)
clear_cookies
post '/api/v3/incoming/validate',
  { recipient: @test_recipient_hash }.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
body = JSON.parse(last_response.body)
body['valid']
#=> true

## POST /api/v3/incoming/validate returns valid:false for unknown hash
@test_recipient_hash = enable_incoming_for_routes(@test_recipient_email)
clear_cookies
post '/api/v3/incoming/validate',
  { recipient: 'nonexistent_hash_xyz' }.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
body = JSON.parse(last_response.body)
body['valid']
#=> false

## POST /api/v3/incoming/validate returns recipient hash in response (not email)
@test_recipient_hash = enable_incoming_for_routes(@test_recipient_email)
clear_cookies
post '/api/v3/incoming/validate',
  { recipient: @test_recipient_hash }.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
body = JSON.parse(last_response.body)
body['recipient'] == @test_recipient_hash
#=> true

## POST /api/v3/incoming/secret returns 200 with valid payload
@test_recipient_hash = enable_incoming_for_routes(@test_recipient_email)
clear_cookies
post '/api/v3/incoming/secret',
  { secret: { secret: 'the actual secret', recipient: @test_recipient_hash, memo: '' } }.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## POST /api/v3/incoming/secret response includes record with receipt key
@test_recipient_hash = enable_incoming_for_routes(@test_recipient_email)
clear_cookies
post '/api/v3/incoming/secret',
  { secret: { secret: 'another secret value', recipient: @test_recipient_hash, memo: 'test' } }.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
body = JSON.parse(last_response.body)
body.dig('record', 'receipt').is_a?(Hash)
#=> true

## POST /api/v3/incoming/secret response includes record with secret key
@test_recipient_hash = enable_incoming_for_routes(@test_recipient_email)
clear_cookies
post '/api/v3/incoming/secret',
  { secret: { secret: 'secret for secret key check', recipient: @test_recipient_hash } }.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
body = JSON.parse(last_response.body)
body.dig('record', 'secret').is_a?(Hash)
#=> true

## POST /api/v3/incoming/secret works without memo (optional field)
@test_recipient_hash = enable_incoming_for_routes(@test_recipient_email)
clear_cookies
post '/api/v3/incoming/secret',
  { secret: { secret: 'secret without memo', recipient: @test_recipient_hash } }.to_json,
  { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

# Teardown
disable_incoming_for_routes(@original_conf)
