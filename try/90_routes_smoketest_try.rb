# frozen_string_literal: true

# These tryouts test the existence of basic routes for web, API, and colonel interfaces.
# We're not testing inputs and outputs, just checking if the routes are supported.
#
# The tryouts use Rack::MockRequest to simulate HTTP requests to the application
# and verify that the routes exist and return appropriate status codes.

require 'rack'
require 'rack/mock'

# Initialize the Rack application and create a mock request
@app = Rack::Builder.parse_file('config.ru').first
@mock_request = Rack::MockRequest.new(@app)

# NOTE: Careful when flushing the Redis database, as it will remove
# all data. Since we organize data types by database number, we can
# flush a specific database to clear only that data type. In this
# case, we're flushing db #2 which is used only for limiter keys.
Familia.redis(2).flushdb

# Web Routes

## Can access the homepage
response = @mock_request.get('/')
response.status
#=> 200

## Can access the dashboard
response = @mock_request.get('/dashboard')
[response.status, response.headers["Location"]]
#=> [302, "/"]

## Can access the about page
response = @mock_request.get('/about')
response.status
#=> 200


# API Routes

## Can access the API status
response = @mock_request.get('/api/v1/status')
[response.status, response.body]
#=> [200, '{"status":"nominal","locale":"en"}']

## Can access the API share endpoint
response = @mock_request.post('/api/v1/create')
content = JSON.parse(response.body) rescue {}
has_msg = content.slice('message').eql?({'message' => 'You did not provide anything to share'})
[response.status, has_msg, content.keys.sort]
#=> [404, true, ['message', 'shrimp']]

## Can access the API generate endpoint
response = @mock_request.post('/api/v1/generate')
content = JSON.parse(response.body)
[response.status, content["custid"]]
#=> [200, 'anon']


# Colonel Routes

## Can access the colonel dashboard
response = @mock_request.get('/colonel')
response.status
#=> 302

## Can access the colonel customers page
response = @mock_request.get('/colonel/customers')
response.status
#=> 404

## Can access the colonel stats page
response = @mock_request.get('/colonel/stats')
response.status
#=> 404
