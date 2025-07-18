# apps/api/v1/models/rate_limit_try.rb

# These tryouts test the rate limiting functionality in the Onetime application.
# They cover various aspects of rate limiting, including:
#
# 1. Defining and registering rate limit events
# 2. Creating and managing rate limiters
# 3. Checking if limits are exceeded
# 4. Handling exceptions when limits are exceeded
# 5. Redis key management and expiration
# 6. Integration with the RateLimited mixin
# 7. Familia::String inheritance behavior
# 8. Time window management
#
# These tests aim to verify the correct behavior of the RateLimit class
# and RateLimited mixin, which are essential for preventing abuse and ensuring
# fair usage of the application.

require 'securerandom'

require_relative '../../../../tests/helpers/test_models'

# Use the default config file for tests
OT.boot! :test, true

# Setup section - define instance variables accessible across all tryouts
@stamp = RateLimit.eventstamp
@identifier = "tryouts-35+#{SecureRandom.hex[0,8]}"
@limiter = RateLimit.new @identifier, :test_limit

# Create a test class that includes RateLimited
class TestRateLimited
  include TestVersion::Mixins::RateLimited
  attr_accessor :id
  def initialize(id)
    @id = id
  end
  def external_identifier
    "test-#{id}"
  end
end

@test_obj = TestRateLimited.new("abc123")


## Has no events defined before loading them from config
RateLimit.events
#=> {}

## Has events defined
RateLimit.register_events(OT.conf[:limits])
RateLimit.events.class
#=> Hash

## Can register a new event
RateLimit.register_event :test_limit, 3
#=> 3

## Can register multiple events at once
RateLimit.register_events(bulk_limit: 5, api_limit: 10)
[RateLimit.events[:bulk_limit], RateLimit.events[:api_limit]]
#=> [5, 10]

## Uses default limit for unregistered events
RateLimit.event_limit(:unknown_event)
#=> 25

## Redis key is created on instantiation
obj = RateLimit.new @identifier, :definitely_unique_key
obj.exists?
#=> true

## Redis key is created on instantiation
obj = RateLimit.new @identifier, :definitely_unique_key
obj.get
#=> 0

## Creates limiter with proper Redis key format
[@limiter.class, @limiter.rediskey]
#=> [RateLimit, "limiter:#{@identifier}:test_limit:#{@stamp}:counter"]

## Can get the external identifier of the limiter
pp [:identifier, @limiter.identifier, @identifier]
@limiter.external_identifier
#=> @identifier

## Can extract event from Redis key
@limiter.event
#=> :test_limit

## Redis key is created after first increment
p @limiter.incr!
@limiter.exists?
#=> true

## Redis relation key has proper TTL (should be around 1200 seconds / 20 minutes)
ttl = @limiter.realttl
p [:ttl, ttl, @limiter.realttl, @limiter.class.ttl]
(ttl > 1100 && ttl <= 1200)
#=> true

## Redis relation key is updated when parent is updated
before_ttl = @limiter.realttl
p [:before, before_ttl]
@limiter.update_expiration(ttl: 5)
after_ttl = @limiter.realttl
p [:after, after_ttl]
[before_ttl, after_ttl]
#=> [1200, 5]

## Can track multiple increments
@limiter.clear
2.times { @limiter.incr! }
@limiter.count
#=> 2

## Knows when not exceeded
@limiter.exceeded?
#=> false

## Knows when exceeded
begin
  4.times { @limiter.incr! } # Will exceed limit of 3
rescue OT::LimitExceeded => ex
  [ex.class, ex.event, ex.identifier, ex.count]
end
#=> [OT::LimitExceeded, :test_limit, @identifier, 4]

## Can clear limiter data
@limiter.clear
@limiter.redis.exists?(@limiter.rediskey)
#=> false

## RateLimited objects can increment events
@test_obj.event_incr! :test_limit
RateLimit.load(@test_obj.external_identifier, :test_limit).value
#=> 1

## RateLimited objects can get event counts
@test_obj.event_get(:test_limit)
#=> 1

## RateLimited objects can clear events
@test_obj.event_clear! :test_limit
@test_obj.event_get(:test_limit)
#=> 0

## Different events use different Redis keys
limiter1 = RateLimit.new @identifier, :test_limit
limiter2 = RateLimit.new @identifier, :other_limit
[limiter1.rediskey == limiter2.rediskey, limiter1.rediskey.include?("test_limit"), limiter2.rediskey.include?("other_limit")]
#=> [false, true, true]

## Different identifiers use different Redis keys
limiter1 = RateLimit.new "id1", :test_limit
limiter2 = RateLimit.new "id2", :test_limit
[limiter1.rediskey == limiter2.rediskey, limiter1.rediskey.include?("id1"), limiter2.rediskey.include?("id2")]
#=> [false, true, true]

## Time windows are properly rounded
now = Time.now.utc
rounded = now - (now.to_i % (20 * 60)) # 20 minutes in seconds
expected = rounded.strftime('%H%M')
#=> RateLimit.eventstamp

## Time windows round properly at edges
now = Time.now.utc
window_size = 20 * 60 # 20 minutes in seconds
rounded = now - (now.to_i % window_size)
edge = Time.at(rounded.to_i + 1).utc # 1 second after window start
RateLimit.eventstamp == rounded.strftime('%H%M')
#=> true

## Time windows round properly near boundaries
now = Time.now.utc
window_size = 20 * 60 # 20 minutes in seconds
rounded = now - (now.to_i % window_size)
near_edge = Time.at(rounded.to_i + window_size - 1).utc # 1 second before next window
RateLimit.eventstamp == rounded.strftime('%H%M')
#=> true

## Different time windows use different Redis keys
@limiter.clear
window1_stamp = RateLimit.eventstamp
@limiter.incr!
# Create key for next time window (20 minutes later)
next_window = Time.now.utc + (20 * 60)
window2_stamp = next_window.strftime('%H%M')
key1 = "limiter:#{@identifier}:test_limit:#{window1_stamp}:counter"
key2 = "limiter:#{@identifier}:test_limit:#{window2_stamp}:counter"
[key1 == key2, @limiter.redis.exists?(key1), @limiter.redis.exists?(key2)]
#=> [false, true, false]

## Counts are isolated between time windows
@limiter.clear
# Set up data in current window
current_key = @limiter.rediskey
3.times { @limiter.incr! }
@limiter.redis.get(current_key).to_i
#=> 3

## Cleanup: clear all test data
[@limiter, RateLimit.new("id1", :test_limit), RateLimit.new("id2", :test_limit)].each(&:clear)
RateLimit.clear! @test_obj.external_identifier, :test_limit
[:test_limit, :bulk_limit, :api_limit].each do |event|
  RateLimit.clear! @identifier, event
end
