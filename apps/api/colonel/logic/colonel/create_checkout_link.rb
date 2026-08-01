# apps/api/colonel/logic/colonel/create_checkout_link.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'account_identifier'
require_relative '../../../../../apps/web/billing/operations/create_checkout_link'

module ColonelAPI
  module Logic
    module Colonel
      # Create a Stripe Checkout Session ("checkout link") for a customer.
      #
      # Thin adapter over Billing::Operations::CreateCheckoutLink (the single
      # implementation, shared with `bin/ots billing checkout-links create`).
      # This class owns HTTP concerns only (param sanitization, authorization,
      # customer/org resolution, response shape); the op creates the session
      # AND records the AdminAuditEvent — so a support-issued checkout link is
      # audited like every other mutating admin verb (epic #20 CONTRACT 4).
      class CreateCheckoutLink < ColonelAPI::Logic::Base
        include AccountIdentifier

        attr_reader :user_id,
          :user,
          :org,
          :plan,
          :billing_cycle,
          :enable_tax,
          :allow_promotion_codes,
          :result

        def process_params
          # sanitize_account_identifier — NOT sanitize_identifier, which strips
          # '@' and '.' and would destroy the email arm (see AccountIdentifier).
          @user_id       = sanitize_account_identifier(params['user_id'])
          @plan          = sanitize_identifier(params['plan'])
          @billing_cycle = sanitize_identifier(params['billing_cycle'].to_s.empty? ? 'monthly' : params['billing_cycle'])

          @enable_tax            = params['enable_tax'].to_s == 'true'
          @allow_promotion_codes = params['allow_promotion_codes'].to_s == 'true'

          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
          raise_form_error('Plan is required', field: :plan) if plan.to_s.empty?

          return if %w[monthly yearly].include?(billing_cycle)

          raise_form_error("Invalid billing cycle '#{billing_cycle}'. Must be monthly or yearly.", field: :billing_cycle)
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          # Resolve by PUBLIC id (extid) first, then email, then objid —
          # mirrors UpdateUserPlan.
          @user = Onetime::Customer.load_by_extid_or_email(user_id) ||
                  Onetime::Customer.load(user_id)
          raise_not_found('User not found') unless user&.exists?

          raise_form_error('Cannot create checkout link for anonymous user', field: :user_id) if user.anonymous?

          @org = ::Billing::Operations::CreateCheckoutLink.default_org_for(user)
          raise_not_found('Customer has no organization') unless org
        end

        def process
          @result = ::Billing::Operations::CreateCheckoutLink.call(
            customer: user,
            org: org,
            product: plan,
            interval: billing_cycle,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
            enable_tax: enable_tax,
            allow_promotion_codes: allow_promotion_codes,
          )

          raise_form_error(result.reason || 'Failed to create checkout link') if result.failed?

          success_data
        end

        # API CONTRACT (frozen — the frontend builds against this shape).
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
              region: Onetime.billing_config.region,
              tax_enabled: enable_tax,
            },
          }
        end
      end
    end
  end
end
