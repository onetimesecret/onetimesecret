# apps/api/colonel/logic/colonel/set_entitlement_test.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # Set Entitlement Test Mode
      #
      # Allows colonels to override their organization's plan entitlements for testing.
      # The override is session-scoped and automatically cleared on logout.
      #
      # ## Request
      #
      # POST /api/colonel/entitlement-test
      # Body: { planid: "identity_plus_v1_monthly" }  - Set test mode
      #       { planid: null }                         - Clear test mode
      #
      # ## Response
      #
      # Active override:
      # {
      #   status: "active",
      #   test_planid: "identity_plus_v1_monthly",
      #   test_plan_name: "Identity Plus",
      #   actual_planid: "free_v1",
      #   entitlements: ["create_secrets", "custom_domains", ...],
      #   source: "stripe" | "local_config"
      # }
      #
      # Cleared:
      # {
      #   status: "cleared",
      #   actual_planid: "free_v1"
      # }
      #
      # ## Source Indicator
      #
      # - "stripe": Plan loaded from Stripe-synced Redis cache
      # - "local_config": Plan loaded from billing.yaml (Stripe unavailable)
      #
      # ## Security
      #
      # - Requires colonel role
      # - Session-scoped (cleared on logout)
      # - Does not modify actual subscription/billing
      class SetEntitlementTest < ColonelAPI::Logic::Base
        attr_reader :planid, :test_plan_config, :plan_source

        def process_params
          @planid = params[:planid]&.to_s&.strip
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          # If setting a plan, validate it exists
          return unless @planid && !@planid.empty?

          # Try Stripe cache first (production)
          stripe_plan = ::Billing::Plan.load(@planid)
          if stripe_plan
            @plan_source = 'stripe'
            @test_plan_config = {
              name: stripe_plan.name,
              entitlements: stripe_plan.entitlements.to_a,
              limits: stripe_plan.limits.hgetall || {},
            }
            return
          end

          # Fall back to billing.yaml config (dev/standalone)
          config_plan = ::Billing::Plan.load_from_config(@planid)
          if config_plan
            @plan_source = 'local_config'
            @test_plan_config = {
              name: config_plan[:name],
              entitlements: config_plan[:entitlements],
              limits: config_plan[:limits],
            }
            return
          end

          raise_form_error('Invalid plan ID')
        end

        def process
          if @planid.nil? || @planid.empty?
            # Clear test mode
            sess.delete(:entitlement_test_planid)

            {
              status: 'cleared',
              actual_planid: organization&.planid,
            }
          else
            # Set test mode
            sess[:entitlement_test_planid] = @planid

            {
              status: 'active',
              test_planid: @planid,
              test_plan_name: @test_plan_config[:name],
              actual_planid: organization&.planid,
              entitlements: @test_plan_config[:entitlements],
              limits: @test_plan_config[:limits],
              source: @plan_source,
            }
          end
        end
      end
    end
  end
end
