# frozen_string_literal: true


require_relative '../lib/onetime'

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.boot! :app

# NOTE: ABOUT LAMBDAS: We wrap associative arrays in lambdas to
# ensure that identical values are used in each test. What you
# see is what you get. There's no dark magic or any further
# complications. It's just a robust way to keep things DRY.

# URL-encoded data with multiple parameters.
@env_url_encoded_multiple = lambda {
                               {
                                 'REQUEST_METHOD' => 'POST',
  'CONTENT_TYPE' => 'application/x-www-form-urlencoded',
  'rack.input' => StringIO.new('key1=value1%25&key2=value2%')
                               }
}

# URL-encoded data with misplaced percent sign.
@env_url_encoded_misplaced_percent = lambda {
                                        {
                                          'REQUEST_METHOD' => 'POST',
  'CONTENT_TYPE' => 'application/x-www-form-urlencoded',
  'rack.input' => StringIO.new('key=value%with%pe%rcent')
                                        }
}

# JSON payload with percent sign
@env_json = lambda {
               {
                 'REQUEST_METHOD' => 'POST',
  'CONTENT_TYPE' => 'application/json',
  'rack.input' => StringIO.new('{"key":"value%with%pe%rcent"}')
               }
}

# Multipart form-data with percent sign
@env_multipart = lambda {
                    {
                      'REQUEST_METHOD' => 'POST',
  'CONTENT_TYPE' => 'multipart/form-data; boundary=---------------------------abcdefg',
  'rack.input' => StringIO.new(
    "-----------------------------abcdefg\r\n" \
    "Content-Disposition: form-data; name=\"key\"\r\n" \
    "\r\n" \
    "value%with%pe%rcent\r\n" \
    "-----------------------------abcdefg--\r\n"
  )
                    }
}


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
