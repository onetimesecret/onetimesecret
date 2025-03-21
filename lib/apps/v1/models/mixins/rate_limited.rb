# frozen_string_literal: true

module Onetime::Models
  module RateLimited
    def event_incr! event
      # Uses the external identifier of the implementing class to keep
      # track of the event count. e.g. sess.external_identifier.
      OT::RateLimit.incr! external_identifier, event
    end

    def event_get event
      OT::RateLimit.get external_identifier, event
    end

    def event_clear! event
      OT::RateLimit.clear! external_identifier, event
    end

    def external_identifier
      OT.ld "[external_identifier] #{self.class}##{id}"
      raise RuntimeError, "TODO: Implement #{self.class}.external_identifier"
    end
  end
end
