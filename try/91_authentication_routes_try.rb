# try/91_authentication_routes_try.rb

# These tryouts test the authentication-related routes
# and how they respond based on the authentication
# settings in etc/config. (NOTE: In test the file is
# etc/config.test.yaml).
#
# The tryouts for POST requests are disabled because
# are returning 302 nil location responses.
#

require 'rack'
require 'rack/mock'

require_relative 'test_models'

# Initialize the real Rack application and create a mock request
@app = Rack::Builder.parse_file('config.ru') # Tryouts 3.3.1 report this as line try/91_authentication_routes_try.rb:15
@mock_request = Rack::MockRequest.new(@app)


# Web Routes (default settings)

## Authentication is enabled
OT.conf['site']['authentication']['signin']
#=> true

## With default configuration, can access the sign-in page
response = @mock_request.get('/signin')
response.status
#=> 200

## With default configuration, can access the sign-in page
response = @mock_request.get('/signup')
response.status
#=> 200

## With default configuration, can try to sign-in
response = @mock_request.post('/signin', lint: true)
[response.status, response.headers["Location"]]
##=> [302, "/"]

### With default configuration, can try to sign-up
response = @mock_request.post('/signup', lint: true)
[response.status, response.headers["Location"]]
##=> [302, nil]

## With default configuration, dashboard redirects to sign-in
response = @mock_request.get('/dashboard')
[response.status, response.headers["Location"]]
#=> [302, "/"]

# Web Routes (authentication disabled)

## Disable authentication for all routes
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
#=> false

## With auth disabled, can access the sign-in page
response = @mock_request.get('/signin')
response.status
##=> 404

## With auth disabled, can access the sign-in page
response = @mock_request.get('/signup')
response.status
##=> 404

## With auth disabled, can try to sign-in
response = @mock_request.post('/signin')
[response.status, response.headers["Location"]]
##=> 404

### With auth disabled, can try to sign-up
response = @mock_request.post('/signup')
[response.status, response.headers["Location"]]
##=> 404

## With auth disabled, dashboard returns 401
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
# This is a 400 response b/c authentication is disabled in
# the config. A protected endpoint (like /dashboard which is
# for customers_only) returns disabled_response.
response.status
#=> 400

# API v1 Routes

## Can access the API status
response = @mock_request.get('/api/v1/status')
[response.status, response.body]
#=> [200, '{"status":"nominal","locale":"en"}']

## Can access the API share endpoint
response = @mock_request.post('/api/v1/create')
content = Familia::JsonSerializer.parse(response.body)
message = content.delete('message')
[response.status, message]
#=> [404, "You did not provide anything to share"]

## Can access the API generate endpoint
response = @mock_request.post('/api/v1/generate')
content = Familia::JsonSerializer.parse(response.body)
[response.status, content["custid"]]
#=> [200, 'anon']

## Can post to a bogus endpoint and get a 404
response = @mock_request.post('/api/v1/generate2')
content = Familia::JsonSerializer.parse(response.body)
[response.status, content["error"]]
#=> [404, 'Not Found']

# API v2 Routes

## Can access the API status
response = @mock_request.get('/api/v2/status')
[response.status, response.body]
#=> [200, '{"status":"nominal","locale":"en"}']

## Can access the API share endpoint
response = @mock_request.post('/api/v2/secret/conceal', {secret:{secret: 'hello', value: 'world'}})
content = Familia::JsonSerializer.parse(response.body)
message = content.delete('message')
[response.status, message]
#=> [422, "You did not provide anything to share"]

## Can post to a bogus endpoint and get a 404
response = @mock_request.post('/api/v2/generate2')
content = Familia::JsonSerializer.parse(response.body)
[response.status, content["success"], content["error"]]
#=> [404, nil, 'Not Found']

## Can post to a bogus endpoint and get a 404
response = @mock_request.post('/api/v2/colonel/info')
content = Familia::JsonSerializer.parse(response.body)
[response.status, content["success"], content["custid"]]
#=> [404, nil, nil]
