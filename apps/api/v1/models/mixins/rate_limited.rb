# apps/api/v1/models/mixins/rate_limited.rb

module V1
  module Mixins

    module RateLimited
      def event_incr! event
        # Uses the external identifier of the implementing class to keep
        # track of the event count. e.g. sess.external_identifier.
        V1::RateLimit.incr! external_identifier, event
      end

      def event_get event
        V1::RateLimit.get external_identifier, event
      end

      def event_clear! event
        V1::RateLimit.clear! external_identifier, event
      end

      def external_identifier
        OT.ld "[external_identifier] #{self.class}##{id}"
        raise RuntimeError, "TODO: Implement #{self.class}.external_identifier"
      end
    end

  end
end
