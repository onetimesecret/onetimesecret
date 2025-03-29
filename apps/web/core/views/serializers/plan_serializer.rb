# apps/web/core/views/serializers/plan_serializer.rb

module Core
  module Views
    module PlanSerializer
      # - plan, is_paid, default_planid, available_plans, plans_enabled
      def self.serialize(view_vars, i18n)
        output = self.output_template

        output[:available_plans] = Onetime::Plan.plans.transform_values do |plan|
          plan.safe_dump
        end

        plan = Onetime::Plan.plan(cust.planid) unless cust.nil?
        plan ||= Onetime::Plan.plan('anonymous')

        output[:plan] = plan.safe_dump
        output[:is_paid] = plan.paid?
        output[:default_planid] = 'basic'
      end

      private

      def self.output_template
        {}
      end

    end
  end
end
