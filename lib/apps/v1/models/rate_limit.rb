# frozen_string_literal: true

require 'forwardable'

# RateLimit is a Redis-backed rate limiting implementation that tracks
# events within specific time windows. It inherits from Familia::String
# to leverage Redis' atomic increment operations and key expiration.
#
# Each rate limit is identified by:
# - identifier: unique identifier for the limited entity (e.g. IP, user)
# - event: the type of event being limited (e.g. :create_secret)
# - timestamp: rounded to the current time window
#
# The Redis key format is: "limiter:#{identifier}:#{event}:#{timestamp}"
#
# Example:
#   limiter = OT::RateLimit.new("1.2.3.4", :create_secret)
#   begin
#     limiter.incr!
#   rescue OT::LimitExceeded => ex
#     puts "Rate limit exceeded for #{ex.event}"
#   end
#
class Onetime::RateLimit < Familia::Horreum
  extend Forwardable

  # Default limit for events that haven't been explicitly configured
  DEFAULT_LIMIT = 25 unless defined?(OT::RateLimit::DEFAULT_LIMIT)

  feature :expiration
  feature :quantization

  qstamp 20.minutes, pattern: '%H'

  # Time window for rate limiting (inherited by ttl)
  ttl 20.minutes

  prefix :limiter
  suffix :counter

  # limiter:cryt61zzviouw9bhxju71wv64q4yba3:get_page:0240
  identifier [:external_identifier, :event, :timeblock]

  field :external_identifier
  field :event
  field :timeblock

  # Fixed in Familia v1.0.0-rev8 - updates, created fields removed

  # Initialize a new rate limiter
  # @param identifier [String] unique identifier for the limited entity
  # @param event [Symbol] the type of event being limited
  # @return [Onetime::RateLimit]
  def init
    redis.setnx(rediskey, 0) # nx = set if not exists
    update_expiration
  end

  def timeblock
    qstamp pattern: '%H%M'
  end

  # Check if this limiter has exceeded its configured limit
  # @return [Boolean]
  def exceeded?
    self.class.exceeded?(event, count)
  end

  def exists?
    redis.exists?(rediskey)
  end

  def get
    redis.get(rediskey).to_i
  end

  def value
    get
  end

  def to_s
    get
  end

  # Increment the counter and raise OT::LimitExceeded if limit is exceeded
  # @return [Integer] the new count
  # @raise [OT::LimitExceeded] if the limit is exceeded
  def incr!
    count = redis.incr(rediskey)
    update_expiration
    limit = self.class.event_limit(event)
    OT.ld "[OT] #{external_identifier} #{event} #{count}/#{limit}"
    if self.class.exceeded?(event, count)
      raise OT::LimitExceeded.new(external_identifier, event, count)
    end
    count
  end

  alias_method :count, :value

  def clear
    delete!
  end

  class << self
    # Hash of registered events and their limits
    attr_reader :events

    def load(identifier, event)
      new(identifier, event)
    end
  end

  module ClassMethods
    # Increment the counter for an identifier/event pair
    # @param identifier [String] unique identifier for the limited entity
    # @param event [Symbol] the type of event being limited
    # @return [Integer] the new count
    # @raise [OT::LimitExceeded] if the limit is exceeded
    def incr! identifier, event
      lmtr = new identifier, event
      count = lmtr.incr!

      OT.ld ['RateLimit.incr!', event, identifier, count, event_limit(event)].inspect

      if exceeded?(event, count)
        raise OT::LimitExceeded.new(identifier, event, count)
      end

      count
    end
    alias_method :increment!, :incr!

    # Clear the counter for an identifier/event pair
    # @param identifier [String] unique identifier for the limited entity
    # @param event [Symbol] the type of event being limited
    # @return [Boolean] true if the key was deleted
    def clear! identifier, event
      lmtr = new identifier, event
      ret = lmtr.clear
      OT.ld [:clear, event, identifier, ret].inspect
      ret
    end

    # Get the current count for an identifier/event pair
    # @param identifier [String] unique identifier for the limited entity
    # @param event [Symbol] the type of event being limited
    # @return [Integer] the current count
    def get identifier, event
      lmtr = new identifier, event
      lmtr.get
    end

    # Get the configured limit for an event
    # @param event [Symbol] the event to get the limit for
    # @return [Integer] the configured limit or DEFAULT_LIMIT
    def event_limit event
      events[event] || DEFAULT_LIMIT
    end

    # Check if a count exceeds the limit for an event
    # @param event [Symbol] the event to check
    # @param count [Integer] the count to check
    # @return [Boolean] true if the count exceeds the limit
    def exceeded? event, count
      (count) > event_limit(event)
    end

    # Register a new event with its limit
    # @param event [Symbol] the event to register
    # @param count [Integer] the maximum allowed count
    # @return [Integer] the registered limit
    def register_event event, count
      (@events ||= {})[event] = count
    end

    # Register multiple events with their limits
    # @param events [Hash] map of event names to limits
    # @return [Hash] the updated events hash
    def register_events events
      (@events ||= {}).merge! events
    end

    # Get the current time window stamp
    # Time is rounded down to the nearest ttl interval
    # @return [String] formatted timestamp (HHMM)
    def eventstamp
      now = OT.now.to_i
      rounded = now - (now % self.ttl)
      Time.at(rounded).utc.strftime('%H%M')
    end
  end

  extend ClassMethods
end
