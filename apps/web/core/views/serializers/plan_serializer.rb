# apps/web/core/views/serializers/plan_serializer.rb

module Core
  module Views
    module PlanSerializer
      # - plan, is_paid, default_planid, available_plans, plans_enabled
      def self.serialize(view_vars, i18n)
        plans = Onetime::Plan.plans.transform_values do |plan|
          plan.safe_dump
        end
        self[:jsvars][:available_plans] = jsvar(plans)

        @plan = Onetime::Plan.plan(cust.planid) unless cust.nil?
        @plan ||= Onetime::Plan.plan('anonymous')
        @is_paid = plan.paid?

        self[:jsvars][:plan] = jsvar(plan.safe_dump)
        self[:jsvars][:is_paid] = jsvar(@is_paid)
        self[:jsvars][:default_planid] = jsvar('basic')

        # Link to the pricing page can be seen regardless of authentication status
        self[:jsvars][:plans_enabled] = jsvar(site.dig(:plans, :enabled) || false)
      end

      private

      def self.output_template
        {}
      end

    end
  end
end
