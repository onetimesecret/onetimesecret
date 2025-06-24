# apps/api/v2/models/mixins/rate_limited.rb

module V2
  module Mixins
    module RateLimited
      def event_incr!(event)
        unless V2::RateLimit.ready?
          return OT.le("Not limiting #{event} events for #{self.class}")
        end

        # Uses the external identifier of the implementing class to keep
        # track of the event count. e.g. sess.external_identifier.
        V2::RateLimit.incr! external_identifier, event
      end

      def event_get(event)
        V2::RateLimit.get external_identifier, event
      end

      def event_clear!(event)
        V2::RateLimit.clear! external_identifier, event
      end

      def external_identifier
        OT.ld "[external_identifier] #{self.class}##{id}" if OT.debug?
        raise "TODO: Implement #{self.class}.external_identifier"
      end
    end
  end
end
