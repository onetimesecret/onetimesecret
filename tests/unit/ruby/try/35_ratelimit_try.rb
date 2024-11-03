# frozen_string_literal: true

# These tryouts test the rate limiting functionality in the OneTime application.
# They cover various aspects of rate limiting, including:
#
# 1. Defining and registering rate limit events
# 2. Creating and managing rate limiters
# 3. Checking if limits are exceeded
# 4. Handling exceptions when limits are exceeded
# 5. Redis key management and expiration
# 6. Integration with the RateLimited mixin
#
# These tests aim to verify the correct behavior of the OT::RateLimit class
# and RateLimited mixin, which are essential for preventing abuse and ensuring
# fair usage of the application.

require 'onetime'

# Use the default config file for tests
OT::Config.path = File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml')
OT.boot! :test

# Setup section - define instance variables accessible across all tryouts
@stamp = OT::RateLimit.eventstamp
@identifier = "tryouts-#{OT.entropy[0,8]}"
@limiter = OT::RateLimit.new @identifier, :test_limit

# Create a test class that includes RateLimited
class TestRateLimited
  include Onetime::Models::RateLimited
  attr_accessor :id
  def initialize(id)
    @id = id
  end
  def external_identifier
    "test-#{id}"
  end
end

@test_obj = TestRateLimited.new("abc123")

## Has events defined
OT::RateLimit.events.class
#=> Hash

## Can register a new event
OT::RateLimit.register_event :test_limit, 3
#=> 3

## Can retrieve registered event limit
OT::RateLimit.events[:test_limit]
#=> 3

## Creates a limiter with proper Redis key
[@limiter.class, @limiter.rediskey]
#=> [Onetime::RateLimit, "limiter:#{@identifier}:test_limit:#{@stamp}"]

## Redis key does not exist initially
@limiter.redis.exists?(@limiter.rediskey)
#=> false

## Redis key is created after first increment
@limiter.incr!
@limiter.redis.exists?(@limiter.rediskey)
#=> true

## Redis key has proper TTL (should be around 1200 seconds / 20 minutes)
ttl = @limiter.redis.ttl(@limiter.rediskey)
(ttl > 1100 && ttl <= 1200)
#=> true

## Can track multiple increments
2.times { @limiter.incr! }
@limiter.count
#=> 3

## Knows when not exceeded
@limiter.exceeded?
#=> false

## Knows when exceeded
begin
  pp @limiter.incr! # This is the 4th increment
rescue OT::LimitExceeded => ex
  [ex.class, ex.event, ex.identifier]
end
#=> [OT::LimitExceeded, :test_limit, @identifier]

## Can clear limiter data
@limiter.clear
@limiter.redis.exists?(@limiter.rediskey)
#=> false

## RateLimited objects can increment events
@test_obj.event_incr! :test_limit
OT::RateLimit.get(@test_obj.external_identifier, :test_limit)
#=> 1

## RateLimited objects can get event counts
@test_obj.event_get(:test_limit)
#=> 1

## RateLimited objects can clear events
@test_obj.event_clear! :test_limit
@test_obj.event_get(:test_limit)
#=> 0

## Different events use different Redis keys
limiter1 = OT::RateLimit.new @identifier, :test_limit
limiter2 = OT::RateLimit.new @identifier, :other_limit
[limiter1.rediskey == limiter2.rediskey, limiter1.rediskey.include?("test_limit"), limiter2.rediskey.include?("other_limit")]
#=> [false, true, true]

## Different identifiers use different Redis keys
limiter1 = OT::RateLimit.new "id1", :test_limit
limiter2 = OT::RateLimit.new "id2", :test_limit
[limiter1.rediskey == limiter2.rediskey, limiter1.rediskey.include?("id1"), limiter2.rediskey.include?("id2")]
#=> [false, true, true]

## Cleanup: clear all test data
[@limiter, OT::RateLimit.new("id1", :test_limit), OT::RateLimit.new("id2", :test_limit)].each(&:clear)
OT::RateLimit.clear! @test_obj.external_identifier, :test_limit
