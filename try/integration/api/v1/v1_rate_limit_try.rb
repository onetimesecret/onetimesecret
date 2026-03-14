# try/integration/api/v1/v1_rate_limit_try.rb
#
# frozen_string_literal: true

# Integration test: V1 rate limiting contract [#2621]
#
# Verifies that V1 endpoints enforce per-IP rate limits using Redis
# counters with a fixed 20-minute window, matching v0.23.x behavior.
# Rate limits are now enforced externally (infrastructure layer), so
# this is vestigial — these tests confirm the V1 API contract only.
#
# v0.23 limits (from etc/defaults/config.defaults.yaml):
#   create_secret: 1000 per 20-min window
#   show_secret:   1000 per 20-min window

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

# Flush all keys to start clean
Familia.dbclient.flushdb

# -----------------------------------------------------------------------
# TEST: Rate limit constants match v0.23 config
# -----------------------------------------------------------------------

## TC-1: V1_RATE_LIMIT_WINDOW is 20 minutes (1200 seconds)
V1::ControllerBase::V1_RATE_LIMIT_WINDOW
#=> 1200

## TC-2: V1_RATE_LIMIT_MAX_CREATES matches v0.23 create_secret limit
V1::ControllerBase::V1_RATE_LIMIT_MAX_CREATES
#=> 1000

## TC-3: V1_RATE_LIMIT_MAX_READS matches v0.23 show_secret limit
V1::ControllerBase::V1_RATE_LIMIT_MAX_READS
#=> 1000

# -----------------------------------------------------------------------
# TEST: Rate limit counter mechanics (Redis INCR + EXPIRE)
# -----------------------------------------------------------------------

## TC-4: First request to /api/v1/share creates a rate limit counter key
Familia.dbclient.flushdb
@mock_request.post('/api/v1/share')
keys = Familia.redis.keys('v1:ratelimit:create_secret:*')
keys.size
#=> 1

## TC-5: Rate limit key has a TTL set (fixed window, not permanent)
key = Familia.redis.keys('v1:ratelimit:create_secret:*').first
ttl = Familia.redis.ttl(key)
ttl > 0 && ttl <= 1200
#=> true

## TC-6: Subsequent request increments the same counter (not a new key)
@mock_request.post('/api/v1/share')
count = Familia.redis.get(Familia.redis.keys('v1:ratelimit:create_secret:*').first).to_i
count
#=> 2

## TC-7: Generate endpoint uses the same create_secret rate limit bucket
Familia.dbclient.flushdb
@mock_request.post('/api/v1/generate')
keys = Familia.redis.keys('v1:ratelimit:create_secret:*')
keys.size
#=> 1

# -----------------------------------------------------------------------
# TEST: Rate limit enforcement (artificially set counter near limit)
# -----------------------------------------------------------------------

## TC-8: Request succeeds when counter is below limit
Familia.dbclient.flushdb
response = @mock_request.post('/api/v1/generate')
response.status
#=> 200

## TC-9: Request is rejected when counter exceeds limit
# Artificially set counter to the max to trigger rate limiting
key_pattern = 'v1:ratelimit:create_secret:*'
key = Familia.redis.keys(key_pattern).first
Familia.redis.set(key, V1::ControllerBase::V1_RATE_LIMIT_MAX_CREATES)
Familia.redis.expire(key, 1200)
response = @mock_request.post('/api/v1/generate')
body = JSON.parse(response.body)
body['message'].include?('Rate limit')
#=> true

# -----------------------------------------------------------------------
# TEST: Cleanup
# -----------------------------------------------------------------------

## TC-10: Clean up rate limit keys after tests
Familia.dbclient.flushdb
Familia.redis.keys('v1:ratelimit:*').size
#=> 0
