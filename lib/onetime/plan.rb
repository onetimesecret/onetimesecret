
module Onetime
  class Plan
    extend Familia::Features::SafeDump::ClassMethods

    @safe_dump_fields = [
      { :identifier => ->(obj) { obj.planid } },
      :planid, :price, :discount, :options
    ]

    attr_reader :planid, :price, :discount, :options

    def initialize(planid, price, discount, options = {})
      @planid = self.class.normalize(planid)
      @price = price
      @discount = discount
      @options = options

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
      attr_reader :plans

      def add_plan(planid, *args)
        @plans ||= {}
        new_plan = new(planid, *args)
        plans[new_plan.planid] = new_plan
        plans[new_plan.planid.gibbler.short] = new_plan
      end

      def normalize(planid)
        planid.to_s.downcase
      end

      def plan(planid)
        plans[normalize(planid)]
      end

      def plan?(planid)
        plans.member?(normalize(planid))
      end

      def load_plans!
        # Plan TTL limits can be overridden via environment variables.
        # This allows Docker deployments to customize max TTL without modifying code.
        # Format: PLAN_TTL_ANONYMOUS=2592000 (value in seconds, e.g., 30 days)
        anonymous_ttl = parse_ttl_env('PLAN_TTL_ANONYMOUS', 7.days)
        basic_ttl = parse_ttl_env('PLAN_TTL_BASIC', 14.days)
        identity_ttl = parse_ttl_env('PLAN_TTL_IDENTITY', 30.days)

        add_plan :anonymous, 0, 0, ttl: anonymous_ttl, size: 100_000, api: false, name: 'Anonymous'
        add_plan :basic, 0, 0, ttl: basic_ttl, size: 1_000_000, api: true, name: 'Basic Plan', email: true, custom_domains: false, dark_mode: true
        add_plan :identity, 35, 0, ttl: identity_ttl, size: 10_000_000, api: true, name: 'Identity', email: true, custom_domains: true, dark_mode: true
      end

      # Parse TTL from environment variable, returning default if not set or invalid.
      # @param env_var [String] Name of the environment variable
      # @param default [Integer] Default TTL in seconds
      # @return [Integer] TTL value in seconds
      def parse_ttl_env(env_var, default)
        value = ENV[env_var]
        return default if value.nil? || value.empty?

        parsed = value.to_i
        parsed.positive? ? parsed : default
      end
    end

    extend ClassMethods
  end
end
