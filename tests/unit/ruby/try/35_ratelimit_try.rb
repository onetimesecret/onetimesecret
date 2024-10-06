# frozen_string_literal: true

# These tryouts test the rate limiting functionality in the OneTime application.
# They cover various aspects of rate limiting, including:
#
# 1. Defining and registering rate limit events
# 2. Creating and managing rate limiters
# 3. Checking if limits are exceeded
# 4. Handling exceptions when limits are exceeded
#
# These tests aim to verify the correct behavior of the OT::RateLimit class,
# which is essential for preventing abuse and ensuring fair usage of the application.
#
# The tryouts simulate different rate limiting scenarios and test the OT::RateLimit class's
# behavior without needing to run the full application, allowing for targeted testing
# of these specific features.


require 'onetime'

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'config.test.yaml')
OT.boot! :test

@stamp = OT::RateLimit.eventstamp

## Has events defined
OT::RateLimit.events.class
#=> Hash

## Can define an event
OT::RateLimit.register_event :delano_limit, 3
#=> 3

## Has limit for creating secrets
OT::RateLimit.events[:delano_limit]
#=> 3

## Create limiter
l = OT::RateLimit.new :tryouts, :delano_limit
[l.class, l.rediskey]
#=> [Onetime::RateLimit, "limiter:tryouts:delano_limit:#{@stamp}"]

## Knows when not exceeded
OT::RateLimit.exceeded? :delano_limit, 3
#=> false

## Knows when exceeded
OT::RateLimit.exceeded? :delano_limit, 4
#=> true

## A limited event raises an exception
begin
  4.times { p OT::RateLimit.incr! :tryouts, :delano_limit } # 4 is one more than 3
rescue OT::LimitExceeded => e
  :success
end
#=> :success

l = OT::RateLimit.new :tryouts, :delano_limit
l.clear
