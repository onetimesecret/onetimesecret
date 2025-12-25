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

          # Use centralized fallback loader
          result       = ::Billing::Plan.load_with_fallback(@planid)
          @plan_source = result[:source]

          if result[:plan]
            # Stripe-synced plan
            @test_plan_config = {
              name: result[:plan].name,
              entitlements: result[:plan].entitlements.to_a,
              limits: result[:plan].limits.hgetall || {},
            }
          elsif result[:config]
            # billing.yaml config plan
            @test_plan_config = {
              name: result[:config][:name],
              entitlements: result[:config][:entitlements],
              limits: result[:config][:limits],
            }
          else
            raise_form_error('Invalid plan ID')
          end
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
