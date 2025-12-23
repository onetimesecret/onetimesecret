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
      # Body: { planid: "identity_v1" }  - Set test mode
      #       { planid: null }            - Clear test mode
      #
      # ## Response
      #
      # Active override:
      # {
      #   status: "active",
      #   test_planid: "identity_v1",
      #   test_plan_name: "Identity Plus",
      #   actual_planid: "free",
      #   entitlements: ["create_secrets", "custom_domains", ...]
      # }
      #
      # Cleared:
      # {
      #   status: "cleared",
      #   actual_planid: "free"
      # }
      #
      # ## Security
      #
      # - Requires colonel role
      # - Session-scoped (cleared on logout)
      # - Does not modify actual subscription/billing
      class SetEntitlementTest < ColonelAPI::Logic::Base
        # Minimal fallback plans for dev environments when Billing::Plan cache is empty
        # Used only as last resort - prefer Billing::Plan.load() for actual plan lookup
        FALLBACK_PLANS = {
          'free' => {
            name: 'Free',
            entitlements: %w[create_secrets basic_sharing],
            limits: { 'secrets.max' => '10', 'recipients.max' => '1' },
          },
          'identity_plus_v1_monthly' => {
            name: 'Identity Plus',
            entitlements: %w[create_secrets custom_domains create_organization priority_support],
            limits: { 'secrets.max' => '100', 'recipients.max' => '10', 'organizations.max' => '1' },
          },
          'multi_team_v1_monthly' => {
            name: 'Multi-Team',
            entitlements: %w[create_secrets custom_domains create_organization api_access audit_logs advanced_analytics],
            limits: { 'secrets.max' => 'unlimited', 'recipients.max' => 'unlimited', 'organizations.max' => '5' },
          },
        }.freeze

        attr_reader :planid, :test_plan_config

        def process_params
          @planid = params[:planid]&.to_s&.strip
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          # If setting a plan, validate it exists
          # Check Billing::Plan cache first (production/Stripe-synced), then fallback plans (dev)
          return unless @planid && !@planid.empty?

          actual_plan       = ::Billing::Plan.load(@planid)
          @test_plan_config = if actual_plan
            {
              name: actual_plan.name,
              entitlements: actual_plan.entitlements.to_a,
              limits: actual_plan.limits.hgetall || {},
            }
          else
            # Fall back to minimal dev plans when Billing::Plan cache is empty
            FALLBACK_PLANS[@planid]
                              end

          raise_form_error('Invalid plan ID') unless @test_plan_config
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
            }
          end
        end
      end
    end
  end
end
