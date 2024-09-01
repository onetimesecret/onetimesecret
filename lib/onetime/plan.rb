
module Onetime
  class Plan
    @safe_dump_fields = [:planid, :price, :discount, :options]

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
      # TODO: Doublecheck directly including works as expected. i.e. without subclassing Familia::Horreum.
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
        add_plan :anonymous, 0, 0, ttl: 7.days, size: 100_000, api: false, name: 'Anonymous'
        add_plan :basic, 0, 0, ttl: 14.days, size: 1_000_000, api: true, name: 'Basic Plan', email: true, custom_domains: false, dark_mode: true
        add_plan :identity, 35, 0, ttl: 30.days, size: 10_000_000, api: true, name: 'Identity', email: true, custom_domains: true, dark_mode: true

        # Deprecated / to be removed in future versions
        add_plan :personal_v1, 5.0, 1, ttl: 14.days, size: 1_000_000, api: false, name: 'Personal'
        add_plan :personal_v2, 10.0, 0.5, ttl: 30.days, size: 1_000_000, api: true, name: 'Personal'
        add_plan :personal_v3, 5.0, 0, ttl: 14.days, size: 1_000_000, api: true, name: 'Personal'
        add_plan :professional_v1, 30.0, 0.50, ttl: 30.days, size: 1_000_000, api: true, cname: true,
                                               name: 'Professional'
        add_plan :professional_v2, 30.0, 0.333333, ttl: 30.days, size: 1_000_000, api: true, cname: true,
                                                   name: 'Professional'
        add_plan :agency_v1, 100.0, 0.25, ttl: 30.days, size: 1_000_000, api: true, private: true,
                                          name: 'Agency'
        add_plan :agency_v2, 75.0, 0.33333333, ttl: 30.days, size: 1_000_000, api: true, private: true,                                               name: 'Agency'
        add_plan :basic_v1, 10.0, 0.5, ttl: 30.days, size: 1_000_000, api: true, name: 'Basic'
        add_plan :individual_v1, 0, 0, ttl: 14.days, size: 1_000_000, api: true, name: 'Individual'
        add_plan :nonprofit_v1, 0, 0, ttl: 30.days, size: 1_000_000, api: true, cname: true,
                                      name: 'Non Profit'
      end
    end

    extend ClassMethods
  end
end
