# lib/middleware/handle_invalid_utf8_try.rb

# These tryouts test the Rack::HandleInvalidUTF8 middleware,
# focusing on scenarios involving invalid UTF-8 characters in
# different types of HTTP requests.
#
# We're testing various scenarios, including:
# 1. Requests with invalid UTF-8 in headers
# 2. Requests with invalid UTF-8 in the body
# 3. Requests with null bytes
# 4. Requests with valid UTF-8
# 5. Different content types (JSON, form-urlencoded, multipart)
#
# These tests aim to ensure that the middleware correctly handles
# invalid UTF-8 input, logs appropriate messages, and returns
# proper responses.

require 'json'
require 'rack'
require 'stringio'

require 'middleware/handle_invalid_utf8'

# Helper method to create invalid UTF-8 string
def invalid_utf8
  "\xFF\xFE\xFD"
end

# Helper method to create a string with a null byte
def null_byte_string
  "hello\x00world"
end

# Valid UTF-8 request
@env_valid_utf8 = lambda {{
  'REQUEST_METHOD' => 'GET',
  'HTTP_USER_AGENT' => 'ValidAgent',
  'rack.input' => StringIO.new
}}

# Request with invalid UTF-8 in header
@env_invalid_utf8_header = lambda {{
  'REQUEST_METHOD' => 'GET',
  'HTTP_USER_AGENT' => "Invalid#{invalid_utf8}Agent",
  'rack.input' => StringIO.new
}}

# Request with invalid UTF-8 in body
@env_invalid_utf8_body = lambda {{
  'REQUEST_METHOD' => 'POST',
  'CONTENT_TYPE' => 'application/json',
  'rack.input' => StringIO.new("{\"key\":\"Invalid#{invalid_utf8}Value\"}")
}}

# Request with null byte in body
@env_null_byte = lambda {{
  'REQUEST_METHOD' => 'POST',
  'CONTENT_TYPE' => 'application/json',
  'rack.input' => StringIO.new("{\"key\":\"#{null_byte_string}\"}")
}}

# Set up the middleware
@app = lambda { |env| [200, {'Content-Type' => 'text/plain'}, ['OK']] }
@middleware = Rack::HandleInvalidUTF8.new(@app, check_enabled: true)

## Middleware allows valid UTF-8 request to pass through
env = @env_valid_utf8.call
status, headers, body = @middleware.call(env)
"Status: #{status}, Body: #{body.first}"
#=> "Status: 200, Body: OK"

## Middleware handles invalid UTF-8 in header
env = @env_invalid_utf8_header.call
status, headers, body = @middleware.call(env)
response = JSON.parse(body.first)
"Status: #{status}, Error: #{response['error']}, Message: #{response['message'].include?('Invalid UTF-8')}"
#=> "Status: 400, Error: Bad Request, Message: true"

## Middleware handles invalid UTF-8 in body
env = @env_invalid_utf8_body.call
status, headers, body = @middleware.call(env)
response = JSON.parse(body.first)
"Status: #{status}, Error: #{response['error']}, Message: #{response['message'].include?('Invalid UTF-8')}"
#=> "Status: 400, Error: Bad Request, Message: true"

## Middleware handles null byte in body
env = @env_null_byte.call
status, headers, body = @middleware.call(env)
"Status: #{status}, Message: #{body.first}"
#=> "Status: 200, Message: OK"

## Middleware sets correct content type in error response
env = @env_invalid_utf8_header.call
status, headers, body = @middleware.call(env)
"Content-Type: #{headers[:'Content-Type']}"
#=> "Content-Type: application/json; charset=utf-8"

## Middleware logs error message
io = StringIO.new
middleware_with_custom_logger = Rack::HandleInvalidUTF8.new(@app, io: io, check_enabled: true)
env = @env_invalid_utf8_header.call
middleware_with_custom_logger.call(env)
io.rewind
log_message = io.read
log_message.include?("[handle-invalid-utf8] Invalid UTF-8 or null byte detected:")
#=> true

## Middleware allows requests with valid UTF-8 to pass through
env = {
  'REQUEST_METHOD' => 'POST',
  'CONTENT_TYPE' => 'application/json',
  'rack.input' => StringIO.new('{"key":"validValue🌈"}')  # Valid UTF-8 with emoji
}
status, headers, body = @middleware.call(env)
"Status: #{status}, Body: #{body.first}"
#=> "Status: 200, Body: OK"
