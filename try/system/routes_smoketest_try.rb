# try/system/routes_smoketest_try.rb
#
# frozen_string_literal: true

# These tryouts test the existence of basic routes for web, API, and colonel interfaces.
# We're not testing inputs and outputs, just checking if the routes are supported.
#
# The tryouts use Rack::MockRequest to simulate HTTP requests to the application
# and verify that the routes exist and return appropriate status codes.

require_relative '../support/test_helpers'
OT.boot! :test

require 'rack'
require 'rack/mock'

require 'onetime/middleware'
require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry
Onetime.instance_variable_set(:@ready, true) unless Onetime.ready?

mapped = Onetime::Application::Registry.generate_rack_url_map
@mock_request = Rack::MockRequest.new(mapped)

# NOTE: Careful when flushing the Redis database, as it will remove
# all data. Since we organize data types by database number, we can
# flush a specific database to clear only that data type. In this
# case, we're flushing db #2 which is used only for limiter keys.
Familia.dbclient.flushdb

# Web Routes

## Can access the homepage
response = @mock_request.get('/')
response.status
#=> 200

## Dashboard redirects to signin when not authenticated
response = @mock_request.get('/dashboard')
[response.status, response.headers["location"]]
#=> [302, "/signin"]

## Can access the feedback page
response = @mock_request.get('/feedback')
response.status
#=> 200


# API Routes

## Can access the v1 API status
# NOTE: Disabled pending Otto v2 migration for v1 API (#2128)
response = @mock_request.get('/api/v1/status')
[response.status, response.body]
##=> [200, '{"status":"nominal","locale":"en"}']

## v1 API does not have an authcheck endpoint
# NOTE: Disabled pending Otto v2 migration for v1 API (#2128)
response = @mock_request.get('/api/v1/authcheck')
[response.status, response.body]
##=> [404, "{\"message\":\"Not authorized\"}"]

## Can access the v2 API status
response = @mock_request.get('/api/v2/status')
[response.status, response.body]
#=> [200, '{"success":true,"status":"nominal","locale":"en"}']

## v2 API does not have an authcheck endpoint
response = @mock_request.get('/api/v2/authcheck')
[response.status, response.body]
#=> [404, '{"error":"Not Found"}']

## Can access the API share endpoint
# NOTE: Disabled pending Otto v2 migration for v1 API (#2128)
response = @mock_request.post('/api/v1/create')
content = Familia::JsonSerializer.parse(response.body)
has_msg = content.slice('message').eql?({'message' => 'You did not provide anything to share'})
[response.status, has_msg, content.keys.sort]
##=> [404, true, ['message', 'shrimp']]

## Can access the API generate endpoint
# NOTE: Disabled pending Otto v2 migration for v1 API (#2128)
response = @mock_request.post('/api/v1/generate')
content = Familia::JsonSerializer.parse(response.body)
[response.status, content["custid"]]
##=> [200, 'anon']

## V2 API conceal returns 422 with validation error when no secret provided
# Otto error format: { error: 'FormError', message: '...' }
# NOTE: Accept header required for JSON error responses (Otto content negotiation)
response = @mock_request.post('/api/v2/secret/conceal', 'HTTP_ACCEPT' => 'application/json')
content = Familia::JsonSerializer.parse(response.body)
has_msg = content['message'] == 'You did not provide anything to share'
p response.body
[response.status, has_msg, content.keys.sort]
#=> [422, true, ['error', 'message']]

## V2 API generate creates a secret and returns success with nested record data
response = @mock_request.post('/api/v2/secret/generate')
content = Familia::JsonSerializer.parse(response.body)
[response.status, content['success']]
#=> [200, true]

## Behaviour when requesting a known non-existent endpoint
response = @mock_request.post('/api/v2/humphrey/bogus')
content = Familia::JsonSerializer.parse(response.body)
has_msg = content.slice('error').eql?({'error' => 'Not Found'})
[response.status, has_msg, content.keys.sort]
#=> [404, true, ['error']]

# API v2 Routes

## Cannot access the colonel dashboard when not authenticated
# NOTE: Disabled - route doesn't exist in current implementation (#2128)
response = @mock_request.get('/api/v2/colonel/info')
response.status
##=> 403
