# apps/api/colonel/logic/colonel/create_organization_checkout_link.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative '../../../../../apps/web/billing/operations/create_checkout_link'

module ColonelAPI
  module Logic
    module Colonel
      # Create a Stripe Checkout Session for a specific organization's owner.
      class CreateOrganizationCheckoutLink < ColonelAPI::Logic::Base
        UNSCOPED_REGION = 'global'

        attr_reader :org_id,
          :org,
          :owner,
          :plan,
          :billing_cycle,
          :allow_promotion_codes,
          :result

        def process_params
          @org_id        = sanitize_identifier(params['org_id'])
          @plan          = sanitize_identifier(params['plan'])
          @billing_cycle = sanitize_identifier(params['billing_cycle'].to_s.empty? ? 'monthly' : params['billing_cycle'])

          @allow_promotion_codes = params['allow_promotion_codes'].to_s == 'true'

          raise_form_error('Organization ID is required', field: :org_id) if org_id.to_s.empty?
          raise_form_error('Plan is required', field: :plan) if plan.to_s.empty?

          return if %w[monthly yearly].include?(billing_cycle)

          raise_form_error("Invalid billing cycle '#{billing_cycle}'. Must be monthly or yearly.", field: :billing_cycle)
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          @org = load_organization
          raise_not_found('Organization not found') unless org&.exists?

          @owner = org.owner
          raise_not_found('Organization owner not found') unless owner&.exists?

          if owner.anonymous?
            raise_form_error('Cannot create checkout link for anonymous organization owner', field: :org_id)
          end
        end

        def process
          @result = ::Billing::Operations::CreateCheckoutLink.call(
            customer: owner,
            org: org,
            product: plan,
            interval: billing_cycle,
            actor: cust.extid,
            allow_promotion_codes: allow_promotion_codes,
          )

          raise_form_error(result.reason || 'Failed to create checkout link') if result.failed?

          success_data
        end

        def success_data
          {
            record: {
              checkout_url: result.url,
              session_id: result.session_id,
              plan_id: result.plan_id,
              price_id: result.price_id,
              expires_at: result.expires_at.to_i,
            },
            details: {
              region: Onetime.billing_config.region || UNSCOPED_REGION,
            },
          }
        end

        private

        def load_organization
          Onetime::Organization.find_by_extid(org_id) ||
            Onetime::Organization.load(org_id)
        end
      end
    end
  end
end
