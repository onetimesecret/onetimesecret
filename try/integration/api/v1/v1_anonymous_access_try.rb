# try/integration/api/v1/v1_anonymous_access_try.rb
#
# frozen_string_literal: true

# Integration test: V1 anonymous access and custid response validation [#2733]
#
# After removing Customer.anonymous, anonymous API requests must:
# 1. Return HTTP 200 for endpoints that allow anonymous access
# 2. Include custid key in the response body
# 3. Return custid as "anon" (string) for backward compatibility with v0.23.x
#
# Note: v0.23.x V1 API always returned custid="anon" for unauthenticated
# requests. This is preserved in v0.24 for backward compatibility. The
# internal Customer.anonymous stub was removed, but the API response shape
# remains unchanged - anonymous requests get custid="anon" via receipt_hsh.
#
# Endpoints that require authentication must reject anonymous requests.
#
# This test validates the V1 API contract for anonymous users post-refactoring.

require_relative '../../../support/test_helpers'
OT.boot! :test

require 'rack'
require 'rack/mock'

require 'onetime/middleware'
require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry
Onetime.started! unless Onetime.ready?

mapped = Onetime::Application::Registry.generate_rack_url_map
@mock_request = Rack::MockRequest.new(mapped)

# Mock requests need REMOTE_ADDR for proper request handling
@mock_env = { 'REMOTE_ADDR' => '198.51.100.42' }

# Flush limiter keys (db #2) to avoid rate-limit interference
Familia.dbclient.flushdb

# -----------------------------------------------------------------------
# TEST: POST /api/v1/create without auth
# -----------------------------------------------------------------------

## TC-1: POST /api/v1/create with secret returns HTTP 200
response = @mock_request.post('/api/v1/create', @mock_env.merge(
  'rack.input' => StringIO.new('secret=test-secret-for-create')
))
response.status
#=> 200

## TC-2: POST /api/v1/create response contains custid key
response = @mock_request.post('/api/v1/create', @mock_env.merge(
  'rack.input' => StringIO.new('secret=test-secret-for-create-2')
))
body = JSON.parse(response.body)
body.key?('custid')
#=> true

## TC-3: POST /api/v1/create returns custid as "anon" for anonymous users
# V1 API contract: anonymous requests get custid="anon" for v0.23.x compatibility
response = @mock_request.post('/api/v1/create', @mock_env.merge(
  'rack.input' => StringIO.new('secret=test-secret-for-create-3')
))
body = JSON.parse(response.body)
body['custid']
#=> 'anon'

# -----------------------------------------------------------------------
# TEST: POST /api/v1/share without auth (full test)
# -----------------------------------------------------------------------

## TC-4: POST /api/v1/share with secret returns HTTP 200
response = @mock_request.post('/api/v1/share', @mock_env.merge(
  'rack.input' => StringIO.new('secret=test-secret-for-share')
))
response.status
#=> 200

## TC-5: POST /api/v1/share response contains custid key
response = @mock_request.post('/api/v1/share', @mock_env.merge(
  'rack.input' => StringIO.new('secret=test-secret-for-share-2')
))
body = JSON.parse(response.body)
body.key?('custid')
#=> true

## TC-6: POST /api/v1/share returns custid as "anon" for anonymous users
# V1 API contract: anonymous requests get custid="anon" for v0.23.x compatibility
response = @mock_request.post('/api/v1/share', @mock_env.merge(
  'rack.input' => StringIO.new('secret=test-secret-for-share-3')
))
body = JSON.parse(response.body)
body['custid']
#=> 'anon'

# -----------------------------------------------------------------------
# TEST: GET /api/v1/private/:key without auth (receipt retrieval)
# -----------------------------------------------------------------------

## TC-7: Create a secret to get a receipt key for testing
create_response = @mock_request.post('/api/v1/create', @mock_env.merge(
  'rack.input' => StringIO.new('secret=test-secret-for-receipt-test')
))
create_body = JSON.parse(create_response.body)
@receipt_key = create_body['metadata_key']
@receipt_key.nil? == false
#=> true

## TC-8: GET /api/v1/private/:key returns HTTP 200 for valid receipt
response = @mock_request.get("/api/v1/private/#{@receipt_key}", @mock_env)
response.status
#=> 200

## TC-9: GET /api/v1/private/:key response contains custid key
response = @mock_request.get("/api/v1/private/#{@receipt_key}", @mock_env)
body = JSON.parse(response.body)
body.key?('custid')
#=> true

## TC-10: GET /api/v1/private/:key returns custid as "anon" for anonymous users
# V1 API contract: anonymous requests get custid="anon" for v0.23.x compatibility
response = @mock_request.get("/api/v1/private/#{@receipt_key}", @mock_env)
body = JSON.parse(response.body)
body['custid']
#=> 'anon'

# -----------------------------------------------------------------------
# TEST: POST /api/v1/private/:key/burn without auth
# -----------------------------------------------------------------------

## TC-11: Create a secret to burn for testing
create_response = @mock_request.post('/api/v1/create', @mock_env.merge(
  'rack.input' => StringIO.new('secret=test-secret-for-burn-test')
))
create_body = JSON.parse(create_response.body)
@burn_receipt_key = create_body['metadata_key']
@burn_receipt_key.nil? == false
#=> true

## TC-12: POST /api/v1/private/:key/burn returns HTTP 200
response = @mock_request.post("/api/v1/private/#{@burn_receipt_key}/burn", @mock_env)
response.status
#=> 200

## TC-13: POST /api/v1/private/:key/burn response state contains custid key
# Note: burn response has nested state object with receipt data
create_response = @mock_request.post('/api/v1/create', @mock_env.merge(
  'rack.input' => StringIO.new('secret=test-secret-for-burn-test-2')
))
@burn_key_2 = JSON.parse(create_response.body)['metadata_key']
response = @mock_request.post("/api/v1/private/#{@burn_key_2}/burn", @mock_env)
@burn_body = JSON.parse(response.body)
@burn_body['state'].key?('custid')
#=> true

## TC-14: POST /api/v1/private/:key/burn returns custid as "anon" for anonymous users
# V1 API contract: anonymous requests get custid="anon" for v0.23.x compatibility
@burn_body['state']['custid']
#=> 'anon'

# -----------------------------------------------------------------------
# TEST: Anonymous POST /api/v1/secret/:key (reveal) works for anonymous
# -----------------------------------------------------------------------

## TC-15: Create a secret to reveal for testing status code
create_response = @mock_request.post('/api/v1/create', @mock_env.merge(
  'rack.input' => StringIO.new('secret=test-secret-value-for-status')
))
create_body = JSON.parse(create_response.body)
@secret_key_for_status = create_body['secret_key']
@secret_key_for_status.nil? == false
#=> true

## TC-16: POST /api/v1/secret/:key returns HTTP 200 for valid secret
# Note: This reveals and consumes the secret (one-time use)
response = @mock_request.post("/api/v1/secret/#{@secret_key_for_status}", @mock_env)
response.status
#=> 200

## TC-17: POST /api/v1/secret/:key returns the secret value
# Note: Need a fresh secret since TC-16 consumed the previous one
create_response = @mock_request.post('/api/v1/create', @mock_env.merge(
  'rack.input' => StringIO.new('secret=test-secret-value-for-reveal')
))
@secret_key_for_value = JSON.parse(create_response.body)['secret_key']
response = @mock_request.post("/api/v1/secret/#{@secret_key_for_value}", @mock_env)
body = JSON.parse(response.body)
body['value']
#=> 'test-secret-value-for-reveal'

# Note: show_secret endpoint does not include custid in response
# (it returns value, secret_key, share_domain only)

## TC-18: POST /api/v1/secret/:key response contains secret_key and share_domain
create_response = @mock_request.post('/api/v1/create', @mock_env.merge(
  'rack.input' => StringIO.new('secret=test-secret-for-structure')
))
@secret_key_for_structure = JSON.parse(create_response.body)['secret_key']
response = @mock_request.post("/api/v1/secret/#{@secret_key_for_structure}", @mock_env)
body = JSON.parse(response.body)
[body.key?('value'), body.key?('secret_key'), body.key?('share_domain')]
#=> [true, true, true]

# -----------------------------------------------------------------------
# TEST: Anonymous GET /api/v1/authcheck must reject (auth required)
# -----------------------------------------------------------------------

## TC-19: GET /api/v1/authcheck returns 404 without auth credentials
# V1 API uses 404 (not 401) to obscure resource existence when auth fails
response = @mock_request.get('/api/v1/authcheck', @mock_env)
response.status
#=> 404

# -----------------------------------------------------------------------
# TEST: Anonymous GET /api/v1/receipt/recent must reject (auth required)
# -----------------------------------------------------------------------

## TC-20: GET /api/v1/receipt/recent returns 404 without auth credentials
# V1 API uses 404 (not 401) to obscure resource existence when auth fails
response = @mock_request.get('/api/v1/receipt/recent', @mock_env)
response.status
#=> 404

## TC-21: GET /api/v1/private/recent (legacy alias) returns 404 without auth
response = @mock_request.get('/api/v1/private/recent', @mock_env)
response.status
#=> 404

# -----------------------------------------------------------------------
# TEST: POST /api/v1/generate without auth
# -----------------------------------------------------------------------

## TC-22: POST /api/v1/generate returns 200 without auth credentials
response = @mock_request.post('/api/v1/generate', @mock_env)
response.status
#=> 200

## TC-23: POST /api/v1/generate returns custid='anon' for anonymous request
response = @mock_request.post('/api/v1/generate', @mock_env)
body = JSON.parse(response.body)
body['custid']
#=> 'anon'

## TC-24: POST /api/v1/generate returns generated secret value
response = @mock_request.post('/api/v1/generate', @mock_env)
body = JSON.parse(response.body)
# Generated secrets have a value in the response
[body.key?('value'), body['value'].is_a?(String), body['value'].length > 0]
#=> [true, true, true]

# -----------------------------------------------------------------------
# TEST: Canonical /api/v1/receipt/ paths work anonymously
# -----------------------------------------------------------------------

## TC-25: GET /api/v1/receipt/:key returns 200 for anonymous secret
create_response = @mock_request.post('/api/v1/create', @mock_env.merge(
  'rack.input' => StringIO.new('secret=test-canonical-receipt-endpoint')
))
create_body = JSON.parse(create_response.body)
metadata_key = create_body['metadata_key']
receipt_response = @mock_request.get("/api/v1/receipt/#{metadata_key}", @mock_env)
receipt_response.status
#=> 200

## TC-26: POST /api/v1/receipt/:key/burn works anonymously
create_response = @mock_request.post('/api/v1/create', @mock_env.merge(
  'rack.input' => StringIO.new('secret=test-canonical-burn-endpoint')
))
create_body = JSON.parse(create_response.body)
metadata_key = create_body['metadata_key']
burn_response = @mock_request.post("/api/v1/receipt/#{metadata_key}/burn", @mock_env)
burn_response.status
#=> 200

# -----------------------------------------------------------------------
# TEST: Legacy /api/v1/private/ paths work anonymously
# -----------------------------------------------------------------------

## TC-27: GET /api/v1/private/:key returns 200 for anonymous secret (legacy alias)
create_response = @mock_request.post('/api/v1/create', @mock_env.merge(
  'rack.input' => StringIO.new('secret=test-legacy-private-endpoint')
))
create_body = JSON.parse(create_response.body)
metadata_key = create_body['metadata_key']
private_response = @mock_request.get("/api/v1/private/#{metadata_key}", @mock_env)
private_response.status
#=> 200

## TC-28: POST /api/v1/private/:key/burn works anonymously (legacy alias)
create_response = @mock_request.post('/api/v1/create', @mock_env.merge(
  'rack.input' => StringIO.new('secret=test-legacy-burn-endpoint')
))
create_body = JSON.parse(create_response.body)
metadata_key = create_body['metadata_key']
burn_response = @mock_request.post("/api/v1/private/#{metadata_key}/burn", @mock_env)
burn_response.status
#=> 200

# -----------------------------------------------------------------------
# TEST: Clean up
# -----------------------------------------------------------------------

## TC-29: Clean up rate limit keys after tests
Familia.dbclient.flushdb
Familia.dbclient.keys('v1:ratelimit:*').size
#=> 0
