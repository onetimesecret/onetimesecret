# try/integration/api/v1/v1_status_no_auth_try.rb
#
# frozen_string_literal: true

# Integration test: V1 endpoints respond without authentication.
#
# After renaming auth= to openapi_auth= in V1's routes.txt, Otto's
# RouteAuthWrapper no longer attempts to enforce auth strategies that
# V1 never registered. This test verifies the fix works end-to-end
# by hitting the mounted V1 application via Rack::MockRequest.
#
# The key regression test is TC-1: if auth= were still present, Otto
# would return 401 because V1 never registers strategies with Otto.

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

# Flush limiter keys (db #2) to avoid rate-limit interference
Familia.dbclient.flushdb

# -----------------------------------------------------------------------
# TEST: V1 status endpoint returns 200, not 401
# -----------------------------------------------------------------------

## TC-1: GET /api/v1/status returns 200 without any auth credentials
# This is the primary regression test. With auth= in routes.txt, Otto's
# RouteAuthWrapper would reject the request with 401 because V1 never
# registers auth strategies. With openapi_auth=, Otto skips enforcement.
response = @mock_request.get('/api/v1/status')
response.status
#=> 200

## TC-2: V1 status response body is valid JSON
response = @mock_request.get('/api/v1/status')
body = JSON.parse(response.body)
body.is_a?(Hash)
#=> true

## TC-3: V1 status response contains nominal status data
# Otto's JSON response handler wraps the controller output in {success, data}.
# The inner data contains the controller's JSON with status and locale.
response = @mock_request.get('/api/v1/status')
body = JSON.parse(response.body)
inner = body['data'].is_a?(String) ? JSON.parse(body['data']) : body
inner['status']
#=> 'nominal'

# -----------------------------------------------------------------------
# TEST: V1 POST endpoints accept anonymous requests (not blocked by Otto)
# -----------------------------------------------------------------------

## TC-4: POST /api/v1/generate returns 200 without auth credentials
# The generate endpoint allows anonymous access. If Otto were enforcing
# auth= strategies, this would return 401 instead.
response = @mock_request.post('/api/v1/generate')
response.status
#=> 200

## TC-5: POST /api/v1/share returns a response (not 401) without auth
# Even though no secret is provided, the response should be from the
# controller (404 with error message), not a 401 from Otto's auth layer.
response = @mock_request.post('/api/v1/share')
[response.status != 401, response.body.include?('did not provide')]
#=> [true, true]
