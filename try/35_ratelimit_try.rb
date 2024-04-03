require 'onetime'

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
[l.class, l.name]
#=> [Onetime::RateLimit, "limiter:tryouts:delano_limit:#{@stamp}"]

## Knows when not exceeded
OT::RateLimit.exceeded? :delano_limit, 3
#=> false

## Knows when exceeded
OT::RateLimit.exceeded? :delano_limit, 4
#=> true

## A limited event raises an exception
begin
  4.times { p OT::RateLimit.incr! :tryouts, :delano_limit }  # 4 is one more than 3
rescue OT::LimitExceeded => ex
  :success
end
#=> :success

l = OT::RateLimit.new :tryouts, :delano_limit
l.clear