# frozen_string_literal: true

module Onetime
  module Entropy
    # TODO: To be removed altogether. The Entropy values already are not
    # used any more for generating digests.
    @values = Familia::Set.new name.to_s.downcase.gsub('::', Familia.delim).to_sym, db: 11
    class << self
      attr_reader :values
      def count
        values.size
      end
      def empty?
        count.zero?
      end
      def pop
        values.pop ||
        [caller, rand].gibbler.shorten(12).to_s
      end
      def generate count=nil
        count ||= 10_000
        stack = caller
        randval = SecureRandom.hex
        newvalues = []
        values.redis.multi do |pipeline|
          newvalues = (0...count).to_a.collect do |idx|
            val = [OT.instance, stack, randval, Time.now.to_f, idx].gibbler.shorten(12)
            pipeline.sadd? values.rediskey, val
          end
        end
        newvalues.size
      end
    end
  end
end
