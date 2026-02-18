# tests/unit/ruby/try/91_incoming_routes_try.rb

# HTTP-level integration tests for the three incoming secret endpoints.
# Verifies allow_anonymous: true behavior and actual HTTP responses.
#
# Unlike the logic-level tests in 60_logic/60_incoming/, these tests
# exercise the full Rack stack: middleware, controller, and logic.

require_relative './test_helpers'

require 'v1/application'

ENV['INCOMING_ENABLED'] = 'true'
ENV['INCOMING_MEMO_MAX_LENGTH'] = '50'
ENV['INCOMING_DEFAULT_TTL'] = '604800'
ENV['INCOMING_DEFAULT_PASSPHRASE'] = 'http-test-pass'
ENV['INCOMING_RECIPIENT_1'] = 'support@example.com,Support Team'
ENV['INCOMING_RECIPIENT_2'] = 'security@example.com,Security Team'

OT.boot! :test, false

require 'rack'
require 'rack/mock'
require 'json'

builder = Rack::Builder.parse_file('config.ru')
@app = builder.first
mapped = Rack::URLMap.new(AppRegistry.build)
@mock_request = Rack::MockRequest.new(mapped)

# Flush rate limit db to avoid test interference
Familia.redis(2).flushdb

# Get a valid recipient hash for use in tests
@support_hash = OT.incoming_public_recipients.find { |r| r[:name] == 'Support Team' }[:hash]

## GET /api/v2/incoming/config returns 200 with anonymous access
response = @mock_request.get('/api/v2/incoming/config')
content = JSON.parse(response.body)
[response.status, content['config']['enabled']]
#=> [200, true]

## GET /api/v2/incoming/config includes recipients list
response = @mock_request.get('/api/v2/incoming/config')
content = JSON.parse(response.body)
recipients = content['config']['recipients']
[recipients.length >= 2, recipients[0].key?('hash'), recipients[0].key?('name')]
#=> [true, true, true]

## GET /api/v2/incoming/config does not expose email addresses
response = @mock_request.get('/api/v2/incoming/config')
content = JSON.parse(response.body)
recipients = content['config']['recipients']
recipients.none? { |r| r.key?('email') }
#=> true

## POST /api/v2/incoming/validate returns 200 for valid recipient hash
response = @mock_request.post('/api/v2/incoming/validate',
  input: "recipient=#{@support_hash}",
  'CONTENT_TYPE' => 'application/x-www-form-urlencoded')
content = JSON.parse(response.body)
[response.status, content['valid']]
#=> [200, true]

## POST /api/v2/incoming/validate returns 200 for invalid hash (valid: false)
response = @mock_request.post('/api/v2/incoming/validate',
  input: 'recipient=invalidhash12345',
  'CONTENT_TYPE' => 'application/x-www-form-urlencoded')
content = JSON.parse(response.body)
[response.status, content['valid']]
#=> [200, false]

## POST /api/v2/incoming/secret succeeds with anonymous access
response = @mock_request.post('/api/v2/incoming/secret',
  input: "secret[secret]=test+secret+content&secret[memo]=Test+memo&secret[recipient]=#{@support_hash}",
  'CONTENT_TYPE' => 'application/x-www-form-urlencoded')
[response.status, response.status < 500]
#=> [200, true]

## POST /api/v2/incoming/secret returns metadata and secret keys in response
response = @mock_request.post('/api/v2/incoming/secret',
  input: "secret[secret]=another+secret&secret[memo]=Another+memo&secret[recipient]=#{@support_hash}",
  'CONTENT_TYPE' => 'application/x-www-form-urlencoded')
content = JSON.parse(response.body)
content['record']['metadata'].key?('key') && content['record']['secret'].key?('key')
#=> true

# Teardown
ENV.delete('INCOMING_ENABLED')
ENV.delete('INCOMING_MEMO_MAX_LENGTH')
ENV.delete('INCOMING_DEFAULT_TTL')
ENV.delete('INCOMING_DEFAULT_PASSPHRASE')
ENV.delete('INCOMING_RECIPIENT_1')
ENV.delete('INCOMING_RECIPIENT_2')
