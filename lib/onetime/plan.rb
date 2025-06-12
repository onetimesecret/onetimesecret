# lib/onetime/plan.rb

module Onetime
  class Plan
    extend Familia::Features::SafeDump::ClassMethods

    @safe_dump_fields = [
      { identifier: ->(obj) { obj.planid } },
      :planid, :price, :discount, :options
    ].freeze

    attr_reader :planid, :price, :discount, :options

    def initialize(planid, price, discount, options = {})
      @planid   = self.class.normalize(planid)
      @price    = price
      @discount = discount
      @options  = options

      # Include dynamically here at instantiation time to avoid
      # circular dependency issues. Plans are loaded very early
      # ans technically aren't models in the traditional sense.
      #
      self.class.include Familia::Features::SafeDump
    end

    def calculated_price
      (price * (1 - discount)).to_i
    end

    def paid?
      !free?
    end

    def free?
      calculated_price.zero?
    end

    module ClassMethods
      attr_accessor :plans

      def add_plan(planid, *)
        new_plan                             = new(planid, *)
        plans[new_plan.planid]               = new_plan
        plans[new_plan.planid.gibbler.short] = new_plan
      end

      def normalize(planid)
        planid.to_s.downcase
      end

      def plan(planid)
        plans[normalize(planid)] #unless planid.nil?
      end

      def plan?(planid)
        planid.nil? ? false : plans.member?(normalize(planid))
      end

      def load_plans!
        add_plan :anonymous, 0, 0, ttl: 7.days, size: 100_000, api: false, name: 'Anonymous'
        add_plan :basic, 0, 0, ttl: 14.days, size: 1_000_000, api: true, name: 'Basic Plan', email: true,
          custom_domains: false, dark_mode: true
        add_plan :identity, 35, 0, ttl: 30.days, size: 10_000_000, api: true, name: 'Identity', email: true,
          custom_domains: true, dark_mode: true
        self.plans.freeze
      end
    end

    extend ClassMethods
  end
end
