# apps/web/frontend/views/serializers/plan_serializer.rb

module Frontend
  module Views
    # Serializes subscription plan data for the frontend
    #
    # Responsible for transforming customer plan information, available plans,
    # and plan-related settings into a consistent format for frontend consumption.
    module PlanSerializer
      # Serializes plan data from view variables
      #
      # @param view_vars [Hash] The view variables containing plan information
      # @param i18n [Object] The internationalization instance
      # @return [Hash] Serialized plan data including current plan and available plans
      def self.serialize(view_vars, _i18n)
        output = self.output_template

        cust = view_vars[:cust]

        output[:available_plans] = Onetime::Plan.plans.transform_values do |plan|
          plan.safe_dump
        end

        plan   = Onetime::Plan.plan(cust.planid) unless cust.nil?
        plan ||= Onetime::Plan.plan('anonymous')

        output[:plan]           = plan&.safe_dump
        output[:is_paid]        = plan&.paid? || false
        output[:default_planid] = 'basic'

        output
      end

      class << self
        # Provides the base template for plan serializer output
        #
        # @return [Hash] Template with all possible plan output fields
        def output_template
          {
            plan: nil,
            is_paid: nil,
            default_planid: nil,
            available_plans: nil,
          }
        end
      end

      SerializerRegistry.register(self)
    end
  end
end
