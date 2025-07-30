
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

      def load_billing

        plans_data = OT.conf&.dig(:billing, :plans) || {}

        plans_data.each do |planid, plan_data|
          add_plan planid, plan_data[:options]
        end
      end
    end

    extend ClassMethods
  end
end

__END__

:plans:
  :anonymous:
    :options:
      :ttl: 7.days
      :size: 100_000
      :api: false
      :name: 'Anonymous'
  :basic:
    :options:
      :ttl: 14.days
      :size: 1_000_000
      :api: true
      :name: 'Basic Plan'
      :email: true
      :custom_domains: false
  :identity:
    :options:
      :ttl: 30.days
      :size: 10_000_000
      :api: true
      :name: 'Identity'
      :email: true
      :custom_domains: true
