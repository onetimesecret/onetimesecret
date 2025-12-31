# apps/web/billing/controllers/billing.rb
#
# frozen_string_literal: true

require 'stripe'

require_relative 'base'
require_relative '../lib/stripe_client'

module Billing
  module Controllers
    class BillingController
      include Controllers::Base

      # Get billing overview for organization
      #
      # Returns current subscription status, plan details, and usage information.
      #
      # GET /billing/org/:extid
      #
      # @return [Hash] Billing overview data
      def overview
        org = load_organization(req.params['extid'])

        data = {
          organization: {
            id: org.extid,  # Use extid (external ID) for API, not objid (internal ID)
            display_name: org.display_name,
            billing_email: org.billing_email,
          },
          subscription: build_subscription_data(org),
          plan: build_plan_data(org),
          usage: build_usage_data(org),
        }

        json_response(data)
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue StandardError => ex
        billing_logger.error 'Failed to load billing overview', {
          exception: ex,
          extid: req.params['extid'],
        }
        json_error('Failed to load billing data', status: 500)
      end

      # Create checkout session for organization
      #
      # Creates a new Stripe Checkout Session for the organization to subscribe
      # or change their plan.
      #
      # POST /billing/org/:extid/checkout
      #
      # @param [String] tier Plan tier (from request body)
      # @param [String] billing_cycle Billing cycle (from request body)
      #
      # @return [Hash] Checkout session URL
      def create_checkout_session
        org = load_organization(req.params['extid'], require_owner: true)

        tier          = req.params['tier']
        billing_cycle = req.params['billing_cycle']

        unless tier && billing_cycle
          return json_error('Missing tier or billing_cycle', status: 400)
        end

        # Detect region
        region = detect_region

        # Get plan from cache
        plan = ::Billing::Plan.get_plan(tier, billing_cycle, region)

        unless plan
          billing_logger.warn 'Plan not found', {
            tier: tier,
            billing_cycle: billing_cycle,
            region: region,
          }
          return json_error('Plan not found', status: 404)
        end

        # Build checkout session parameters
        site_host = Onetime.conf['site']['host']
        is_secure = Onetime.conf['site']['ssl']
        protocol  = is_secure ? 'https' : 'http'

        success_url = "#{protocol}://#{site_host}/billing/welcome?session_id={CHECKOUT_SESSION_ID}"
        cancel_url  = "#{protocol}://#{site_host}/account"

        session_params = {
          mode: 'subscription',
          line_items: [{
            price: plan.stripe_price_id,
            quantity: 1,
          }],
          success_url: success_url,
          cancel_url: cancel_url,
          customer_email: org.billing_email || cust.email,
          client_reference_id: org.objid,
          locale: req.env['rack.locale']&.first || 'auto',
          subscription_data: {
            metadata: {
              orgid: org.objid,
              plan_id: plan.plan_id,
              tier: tier,
              region: region,
              customer_extid: cust.extid,
            },
          },
        }

        # If organization already has a Stripe customer, use it
        if org.stripe_customer_id
          session_params[:customer] = org.stripe_customer_id
          session_params.delete(:customer_email)
        end

        # Create Stripe Checkout Session with idempotency
        # Generate deterministic idempotency key to prevent duplicate sessions
        stripe_client = Billing::StripeClient.new

        # ==========================================================================
        # IDEMPOTENCY KEY - CRITICAL FOR PREVENTING DUPLICATE CHECKOUTS
        # ==========================================================================
        #
        # Stripe caches checkout sessions by idempotency key. If you see
        # "You're all done here" on the checkout page, it means Stripe returned
        # a cached (already-completed) session instead of creating a new one.
        #
        # KEY BEHAVIOR DIFFERENCE:
        #   - TEST MODE (sk_test_*): Minute granularity - allows rapid iteration
        #   - LIVE MODE (sk_live_*): Daily granularity - prevents accidental duplicates
        #
        # If stuck in test mode: wait 1 minute, or try a different plan tier.
        #
        # SHA256 produces 64 hex chars, well within Stripe's 255 char limit.
        # ==========================================================================
        time_component = if Stripe.api_key&.start_with?('sk_test_')
                           Time.now.strftime('%Y-%m-%dT%H:%M') # Minute granularity for test
                         else
                           Time.now.to_date.iso8601 # Daily for production
                         end
        idempotency_key = Digest::SHA256.hexdigest(
          "checkout:#{org.objid}:#{plan.plan_id}:#{time_component}",
        )

        checkout_session = stripe_client.create(
          Stripe::Checkout::Session,
          session_params,
          idempotency_key: idempotency_key,
        )

        billing_logger.info 'Checkout session created for organization', {
          extid: org.extid,  # Use extid for logging, not objid
          session_id: checkout_session.id,
          tier: tier,
          billing_cycle: billing_cycle,
          idempotency_key: idempotency_key[0..7], # Log prefix for debugging
        }

        json_response({
          checkout_url: checkout_session.url,
          session_id: checkout_session.id,
        },
                     )
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue Stripe::StripeError => ex
        billing_logger.error 'Stripe checkout session creation failed', {
          exception: ex,
          extid: req.params['extid'],
        }
        json_error('Failed to create checkout session', status: 500)
      end

      # List invoices for organization
      #
      # Returns recent invoices from Stripe for the organization's customer.
      #
      # GET /billing/org/:extid/invoices
      #
      # @return [Hash] List of invoices
      def list_invoices
        org = load_organization(req.params['extid'])

        unless org.stripe_customer_id
          return json_response({ invoices: [] })
        end

        # Retrieve invoices from Stripe
        invoices = Stripe::Invoice.list({
          customer: org.stripe_customer_id,
          limit: 12, # Last 12 invoices
        },
                                       )

        invoice_data = invoices.data.map do |invoice|
          {
            id: invoice.id,
            number: invoice.number,
            amount: invoice.total,
            currency: invoice.currency,
            status: invoice.status,
            created: invoice.created,
            due_date: invoice.due_date,
            paid_at: invoice.status_transitions&.paid_at,
            invoice_pdf: invoice.invoice_pdf,
            hosted_invoice_url: invoice.hosted_invoice_url,
          }
        end

        json_response({
          invoices: invoice_data,
          has_more: invoices.has_more,
        },
                     )
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue Stripe::StripeError => ex
        billing_logger.error 'Failed to retrieve invoices', {
          exception: ex,
          extid: req.params['extid'],
        }
        json_error('Failed to retrieve invoices', status: 500)
      end

      # List available billing plans
      #
      # Returns all available plans with their pricing and features.
      #
      # GET /billing/plans
      #
      # @return [Hash] List of plans
      def list_plans
        plans = ::Billing::Plan.list_plans

        # Filter out nil plans, filter by show_on_plans_page, and sort by display_order (ascending - lower values first)
        plan_data = plans
          .compact
          .select { |plan| plan.show_on_plans_page.to_s == 'true' }
          .map do |plan|
            {
              id: plan.plan_id,
              stripe_price_id: plan.stripe_price_id,
              name: plan.name,
              tier: plan.tier,
              interval: plan.interval,
              amount: plan.amount,
              currency: plan.currency,
              region: plan.region,
              features: plan.features.to_a,
              limits: plan.limits_hash.transform_values { |v| v == Float::INFINITY ? -1 : v },
              entitlements: plan.entitlements.to_a,
              display_order: plan.display_order.to_i,
            }
          end
          .sort_by { |p| p[:display_order] } # Ascending: Identity Plus (10) → Org Max (40)

        json_response({ plans: plan_data })
      rescue StandardError => ex
        billing_logger.error 'Failed to list plans', {
          exception: ex,
        }
        json_error('Failed to list plans', status: 500)
      end

      # Get subscription status for organization
      #
      # Returns current subscription details including whether plan switching
      # is available. Used by frontend to determine checkout vs plan change flow.
      #
      # GET /billing/api/org/:extid/subscription
      #
      # @return [Hash] Subscription status and current plan details
      def subscription_status
        org = load_organization(req.params['extid'])

        unless org.active_subscription?
          return json_response({
            has_active_subscription: false,
            current_plan: org.planid,
          })
        end

        # Fetch current subscription from Stripe
        subscription = Stripe::Subscription.retrieve(org.stripe_subscription_id)
        current_item = subscription.items.data.first

        json_response({
          has_active_subscription: true,
          current_plan: org.planid,
          current_price_id: current_item.price.id,
          subscription_item_id: current_item.id,
          subscription_status: subscription.status,
          current_period_end: current_item.current_period_end,
        })
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue Stripe::StripeError => ex
        billing_logger.error 'Failed to retrieve subscription status', {
          exception: ex,
          extid: req.params['extid'],
        }
        json_error('Failed to retrieve subscription status', status: 500)
      end

      # Preview plan change proration
      #
      # Shows what the customer will be charged when switching plans.
      # Returns upcoming invoice preview with proration details.
      #
      # POST /billing/api/org/:extid/preview-plan-change
      #
      # @param [String] new_price_id Stripe price ID to switch to
      #
      # @return [Hash] Proration preview with amounts and dates
      def preview_plan_change
        org          = load_organization(req.params['extid'])
        new_price_id = req.params['new_price_id']

        unless new_price_id
          return json_error('Missing new_price_id', status: 400)
        end

        unless org.active_subscription?
          return json_error('No active subscription to modify', status: 400)
        end

        # Fetch current subscription
        subscription = Stripe::Subscription.retrieve(org.stripe_subscription_id)
        current_item = subscription.items.data.first

        # Guard: same plan
        if current_item.price.id == new_price_id
          return json_error('Already on this plan', status: 400)
        end

        # Guard: legacy plan
        if Billing::PlanHelpers.legacy_plan?(price_id_to_plan_id(new_price_id))
          return json_error('This plan is not available', status: 400)
        end

        # Get preview of upcoming invoice with the plan change
        preview = Stripe::Invoice.upcoming(
          customer: org.stripe_customer_id,
          subscription: org.stripe_subscription_id,
          subscription_items: [{
            id: current_item.id,
            price: new_price_id,
          }],
          subscription_proration_behavior: 'create_prorations',
        )

        # Calculate credit from proration items (negative amounts)
        credit_applied = preview.lines.data
          .select { |line| line.proration && line.amount.negative? }
          .sum(&:amount)
          .abs

        # Get new plan details
        new_price = Stripe::Price.retrieve(new_price_id)

        json_response({
          amount_due: preview.amount_due,
          subtotal: preview.subtotal,
          credit_applied: credit_applied,
          next_billing_date: preview.next_payment_attempt,
          currency: preview.currency,
          current_plan: {
            price_id: current_item.price.id,
            amount: current_item.price.unit_amount,
            interval: current_item.price.recurring&.interval,
          },
          new_plan: {
            price_id: new_price_id,
            amount: new_price.unit_amount,
            interval: new_price.recurring&.interval,
          },
        })
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue Stripe::InvalidRequestError => ex
        billing_logger.warn 'Invalid plan change preview request', {
          exception: ex,
          extid: req.params['extid'],
          new_price_id: new_price_id,
        }
        json_error(ex.message, status: 400)
      rescue Stripe::StripeError => ex
        billing_logger.error 'Failed to preview plan change', {
          exception: ex,
          extid: req.params['extid'],
        }
        json_error('Failed to preview plan change', status: 500)
      end

      # Execute plan change
      #
      # Changes the organization's subscription to a new plan.
      # Uses immediate proration (customer charged/credited on next invoice).
      #
      # POST /billing/api/org/:extid/change-plan
      #
      # @param [String] new_price_id Stripe price ID to switch to
      #
      # @return [Hash] Result of plan change with new plan details
      def change_plan
        org          = load_organization(req.params['extid'], require_owner: true)
        new_price_id = req.params['new_price_id']

        unless new_price_id
          return json_error('Missing new_price_id', status: 400)
        end

        unless org.active_subscription?
          return json_error('No active subscription to modify', status: 400)
        end

        # Fetch current subscription
        subscription = Stripe::Subscription.retrieve(org.stripe_subscription_id)
        current_item = subscription.items.data.first

        # Guard: same plan
        if current_item.price.id == new_price_id
          return json_error('Already on this plan', status: 400)
        end

        # Guard: legacy plan
        if Billing::PlanHelpers.legacy_plan?(price_id_to_plan_id(new_price_id))
          return json_error('This plan is not available', status: 400)
        end

        # Execute the plan change
        updated_subscription = Stripe::Subscription.update(
          org.stripe_subscription_id,
          {
            items: [{
              id: current_item.id,
              price: new_price_id,
            }],
            proration_behavior: 'create_prorations',
          },
        )

        # Update local records immediately (webhook will also fire as backup)
        org.update_from_stripe_subscription(updated_subscription)

        billing_logger.info 'Plan changed successfully', {
          extid: org.extid,
          old_price_id: current_item.price.id,
          new_price_id: new_price_id,
          new_plan: org.planid,
        }

        json_response({
          success: true,
          new_plan: org.planid,
          status: updated_subscription.status,
          current_period_end: updated_subscription.items.data.first.current_period_end,
        })
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue Stripe::InvalidRequestError => ex
        billing_logger.warn 'Invalid plan change request', {
          exception: ex,
          extid: req.params['extid'],
          new_price_id: new_price_id,
        }
        json_error(ex.message, status: 400)
      rescue Stripe::StripeError => ex
        billing_logger.error 'Failed to change plan', {
          exception: ex,
          extid: req.params['extid'],
        }
        json_error('Failed to change plan', status: 500)
      end

      private

      # Convert Stripe price ID to plan ID
      #
      # Looks up the plan associated with a Stripe price ID.
      #
      # @param price_id [String] Stripe price ID
      # @return [String, nil] Plan ID or nil if not found
      def price_id_to_plan_id(price_id)
        plan = ::Billing::Plan.list_plans.find { |p| p&.stripe_price_id == price_id }
        plan&.plan_id
      end

      # Build subscription data for response
      #
      # @param org [Onetime::Organization] Organization instance
      # @return [Hash] Subscription data
      def build_subscription_data(org)
        return nil unless org.stripe_subscription_id

        {
          id: org.stripe_subscription_id,
          status: org.subscription_status,
          period_end: org.subscription_period_end,
          active: org.active_subscription?,
          past_due: org.past_due?,
          canceled: org.canceled?,
        }
      end

      # Build plan data for response
      #
      # @param org [Onetime::Organization] Organization instance
      # @return [Hash, nil] Plan data or nil if no plan
      def build_plan_data(org)
        return nil unless org.planid

        plan = ::Billing::Plan.load(org.planid)
        return nil unless plan

        {
          id: plan.plan_id,
          name: plan.name,
          tier: plan.tier,
          interval: plan.interval,
          amount: plan.amount,
          currency: plan.currency,
          features: plan.features.to_a,
          limits: plan.limits_hash,
        }
      end

      # Build usage data for response
      #
      # @param org [Onetime::Organization] Organization instance
      # @return [Hash] Usage data
      def build_usage_data(org)
        # Basic member counts (teams removed from data schema)
        # Future: Add secret counts, API usage, etc.
        {
          members: org.member_count,
          domains: org.domain_count,
        }
      end
    end
  end
end
