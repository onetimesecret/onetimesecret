# lib/onetime/models/feedback.rb

module Onetime
  class Feedback < Familia::Horreum

    using Familia::Refinements::TimeLiterals

    class_sorted_set :values, dbkey: 'onetime:feedback' # naming for legacy compatibility

    module ClassMethods
      def add(msg)
        values.add msg
        # Auto-trim the set to keep only the most recent 30 days of feedback
        values.remrangebyscore 0, OT.now.to_i - 30.days
      end

      # Returns a Hash like: {"msg1"=>"1322644672", "msg2"=>"1322644668"}
      def all
        ret = values.revrangeraw(0, -1, withscores: true)
        Hash[ret]
      end

      def recent(duration = 30.days, epoint = OT.now.to_i)
        spoint = OT.now.to_i - duration
        ret    = values.rangebyscoreraw(spoint, epoint, withscores: true)
        Hash[ret]
      end
    end

    extend ClassMethods
  end
end
