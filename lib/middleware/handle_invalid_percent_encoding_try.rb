# lib/middleware/handle_invalid_percent_encoding_try.rb

# These tryouts replicate and test edge cases related to
# Rack::Request parameter parsing, specifically focusing on scenarios involving
# percent-encoding in different types of HTTP requests.
#
# We're replicating issues that can occur when handling POST requests with various
# content types, including:
# 1. application/x-www-form-urlencoded with invalid percent-encoding
# 2. multipart/form-data containing percent signs
# 3. application/json payloads with percent signs
# 4. URL-encoded data with multiple parameters and percent signs
# 5. Raw body access for requests containing percent signs
#
# These tests aim to uncover potential issues in Rack's handling of percent-encoded
# characters in different contexts, which is crucial for correctly processing user
# input in web applications, especially when dealing with special characters.
#
# The tryouts simulate different request environments and test Rack::Request's
# behavior without needing to run an actual server, allowing for targeted testing
# of these specific scenarios.

require 'json'
require 'rack'

require 'middleware/handle_invalid_percent_encoding'

# NOTE: We wrap associative arrays in lambdas to ensure that
# identical values are used in each test. What you see is
# what you get. There's no dark magic or any further
# complications. It's just a robust way to keep things DRY.

# URL-encoded data with multiple parameters.
@env_url_encoded_multiple = lambda {{
  'REQUEST_METHOD' => 'POST',
  'CONTENT_TYPE' => 'application/x-www-form-urlencoded',
  'rack.input' => StringIO.new('key1=value1%25&key2=value2%')
}}

# URL-encoded data with misplaced percent sign.
@env_url_encoded_misplaced_percent = lambda {{
  'REQUEST_METHOD' => 'POST',
  'CONTENT_TYPE' => 'application/x-www-form-urlencoded',
  'rack.input' => StringIO.new('key=value%with%pe%rcent')
}}

# JSON payload with percent sign
@env_json = lambda {{
  'REQUEST_METHOD' => 'POST',
  'CONTENT_TYPE' => 'application/json',
  'rack.input' => StringIO.new('{"key":"value%with%pe%rcent"}')
}}

# Multipart form-data with percent sign
@env_multipart = lambda {{
  'REQUEST_METHOD' => 'POST',
  'CONTENT_TYPE' => 'multipart/form-data; boundary=---------------------------abcdefg',
  'rack.input' => StringIO.new(
    "-----------------------------abcdefg\r\n" \
    "Content-Disposition: form-data; name=\"key\"\r\n" \
    "\r\n" \
    "value%with%pe%rcent\r\n" \
    "-----------------------------abcdefg--\r\n"
  )
}}

# Demonstrate how the HandleInvalidPercentEncoding
# middleware can resolve these issues.
@app = lambda { |env| [200, {'content-type' => 'text/plain'}, ['OK']] }
@middleware = Rack::HandleInvalidPercentEncoding.new(@app, check_enabled: true)


## Can handle URL-encoded data with multiple parameters
env = @env_url_encoded_multiple.call
req = Rack::Request.new(env)
begin
  params = req.params
rescue ArgumentError => e
  "Error: #{e.message}"
end
#=> "Error: invalid %-encoding (value2%)"


## Can access raw body
env = @env_url_encoded_misplaced_percent.call
req = Rack::Request.new(env)
"Raw body: #{req.body.read}"
#=> "Raw body: key=value%with%pe%rcent"


## Can handle invalid percent-encoding
env = @env_url_encoded_misplaced_percent.call
req = Rack::Request.new(env)
begin
  params = req.params
rescue ArgumentError => e
  "Error: #{e.message}"
end
#=> "Error: invalid %-encoding (value%with%pe%rcent)"


## Can handle JSON payload with percent sign
env = @env_json.call
req = Rack::Request.new(env)
begin
  body = JSON.parse(req.body.read)
  body.to_json
rescue JSON::ParserError => e
  nil # an exception isn't raised
end
#=> "{\"key\":\"value%with%pe%rcent\"}"


## Can handle multipart form-data with percent sign
env = @env_multipart.call
req = Rack::Request.new(env)
begin
  params = req.params
  "Params: #{params['key']}"
rescue ArgumentError => e
  nil # an exception isn't raised
end
#=> "Params: value%with%pe%rcent"


## Middleware handles invalid percent-encoding in URL-encoded data
env = @env_url_encoded_multiple.call
status, headers, body = @middleware.call(env)
"Status: #{status}, Body: #{body.first}"
#=> "Status: 400, Body: {\"error\":\"Bad Request\",\"message\":\"invalid %-encoding (value2%)\"}"


## Middleware handles invalid percent-encoding in misplaced percent sign
env = @env_url_encoded_misplaced_percent.call
status, headers, body = @middleware.call(env)
"Status: #{status}, Body: #{body.first}"
#=> "Status: 400, Body: {\"error\":\"Bad Request\",\"message\":\"invalid %-encoding (value%with%pe%rcent)\"}"


## Middleware allows valid JSON payload with percent sign to pass through
env = @env_json.call
status, headers, body = @middleware.call(env)
"Status: #{status}, Body: #{body.first}"
#=> "Status: 200, Body: OK"


## Middleware allows valid multipart form-data with percent sign to pass through
env = @env_multipart.call
status, headers, body = @middleware.call(env)
"Status: #{status}, Body: #{body.first}"
#=> "Status: 200, Body: OK"


## Middleware sets correct content type in error response (always json)
env = @env_url_encoded_multiple.call
env['HTTP_ACCEPT'] = 'application/xml'
status, headers, body = @middleware.call(env)
"Content-Type: #{headers[:'content-type']}"
#=> "Content-Type: application/json; charset=utf-8"


## Middleware logs error message
io = StringIO.new
middleware_with_custom_logger = Rack::HandleInvalidPercentEncoding.new(@app, io: io, check_enabled: true)
env = @env_url_encoded_multiple.call
middleware_with_custom_logger.call(env)
io.rewind
log_message = io.read
log_message.include?("invalid %-encoding (value2%)")
#=> true


## Middleware allows requests without invalid percent-encoding to pass through
env = {
  'REQUEST_METHOD' => 'GET',
  'QUERY_STRING' => 'key=value%25',  # Valid percent-encoding
  'rack.input' => StringIO.new
}
status, headers, body = @middleware.call(env)
"Status: #{status}, Body: #{body.first}"
#=> "Status: 200, Body: OK"
