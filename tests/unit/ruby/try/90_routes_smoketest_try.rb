# tests/unit/ruby/try/90_routes_smoketest_try.rb

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

## Can access the v1 API status
response = @mock_request.get('/api/v1/status')
[response.status, response.body]
#=> [200, '{"status":"nominal","locale":"en"}']

## Cannot access the v1 API auth check endpoint
response = @mock_request.get('/api/v1/authcheck')
[response.status, response.body]
#=> [404, "{\"message\":\"Not authorized\"}"]

## Can access the v2 API status
response = @mock_request.get('/api/v2/status')
[response.status, response.body]
#=> [200, '{"status":"nominal","locale":"en"}']

## Cannot access the v2 API auth check endpoint
response = @mock_request.get('/api/v2/authcheck')
[response.status, response.body]
#=> [403, "{\"message\":\"Not authorized\"}"]

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

## Can access the API share endpoint
response = @mock_request.post('/api/v2/secret/create')
content = JSON.parse(response.body) rescue {}
has_msg = content.slice('message').eql?({'message' => 'Not Found'})
[response.status, has_msg, content.keys.sort]
#=> [404, true, ['message']]

## Can access the API generate endpoint
response = @mock_request.post('/api/v2/secret/generate')
content = JSON.parse(response.body)
p [:plop, content]
[response.status, content["custid"]]
#=> [200, 'anon']


# API v2 Routes

## Cannot access the colonel dashboard when not authenticated
response = @mock_request.get('/api/v2/colonel')
response.status
#=> 403
