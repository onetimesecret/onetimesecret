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

        if stripe_api_key_missing?('create_checkout_session')
          return json_error('Billing service temporarily unavailable', status: 503)
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
        time_component  = if Stripe.api_key&.start_with?('sk_test_')
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

        if stripe_api_key_missing?('list_invoices')
          return json_error('Billing service temporarily unavailable', status: 503)
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
          },
                              )
        end

        # Validate Stripe API key is configured before making API calls
        if stripe_api_key_missing?('subscription_status')
          return json_error('Billing service temporarily unavailable', status: 503)
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
        },
                     )
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

        # Validate plan change request
        valid, error_response = validate_plan_change_request(org, new_price_id)
        return error_response unless valid

        if stripe_api_key_missing?('preview_plan_change')
          return json_error('Billing service temporarily unavailable', status: 503)
        end

        # Fetch current subscription
        subscription = Stripe::Subscription.retrieve(org.stripe_subscription_id)
        current_item = subscription.items.data.first

        # Guard: same plan (requires current subscription data)
        if current_item.price.id == new_price_id
          return json_error('Already on this plan', status: 400)
        end

        # Validate target plan is in catalog and not legacy
        valid, error_response = validate_target_plan(new_price_id)
        return error_response unless valid

        # Get preview of upcoming invoice with the plan change
        # Note: Stripe gem v10+ uses 'create_preview' with subscription at top level
        # and item changes inside subscription_details
        preview = Stripe::Invoice.create_preview(
          customer: org.stripe_customer_id,
          subscription: org.stripe_subscription_id,
          subscription_details: {
            items: [{
              id: current_item.id,
              price: new_price_id,
            }],
            proration_behavior: 'create_prorations',
          },
        )

        # Calculate proration breakdown and find new price details
        amounts   = calculate_proration_amounts(preview)
        new_price = find_price_in_preview(preview, new_price_id)

        json_response({
          amount_due: preview.amount_due,
          immediate_amount: amounts[:immediate_amount],
          next_period_amount: amounts[:next_period_amount],
          subtotal: preview.subtotal,
          credit_applied: amounts[:credit_applied],
          next_billing_date: preview.next_payment_attempt,
          currency: preview.currency,
          current_plan: {
            price_id: current_item.price.id,
            amount: current_item.price.unit_amount,
            interval: current_item.price.recurring&.interval,
          },
          new_plan: {
            price_id: new_price_id,
            amount: new_price&.unit_amount,
            interval: new_price&.recurring&.interval,
          },
        },
                     )
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

        # Validate plan change request
        valid, error_response = validate_plan_change_request(org, new_price_id)
        return error_response unless valid

        if stripe_api_key_missing?('change_plan')
          return json_error('Billing service temporarily unavailable', status: 503)
        end

        # Fetch current subscription
        subscription = Stripe::Subscription.retrieve(org.stripe_subscription_id)
        current_item = subscription.items.data.first

        # Guard: same plan (requires current subscription data)
        if current_item.price.id == new_price_id
          return json_error('Already on this plan', status: 400)
        end

        # Validate target plan is in catalog and not legacy
        valid, error_response = validate_target_plan(new_price_id)
        return error_response unless valid

        # Generate idempotency key to prevent duplicate plan changes from
        # network retries. Uses 5-minute windows (300 seconds) so repeated
        # identical requests within the same window are deduplicated by Stripe.
        idempotency_key = Digest::SHA256.hexdigest(
          "plan_change:#{org.stripe_subscription_id}:#{new_price_id}:#{Time.now.to_i / 300}",
        )

        # ==========================================================================
        # PLAN CHANGE DATA FLOW
        # ==========================================================================
        #
        # When a plan change occurs, multiple systems need to stay in sync:
        #
        # 1. STRIPE SUBSCRIPTION
        #    - items[].price.id → updated to new_price_id (e.g., 'price_team_plus_monthly')
        #    - metadata.plan_id → updated to new plan_id (e.g., 'team_plus_v1_monthly')
        #    - metadata.tier → updated to new tier (e.g., 'multi_team')
        #
        # 2. LOCAL ORGANIZATION RECORD (Redis via Familia)
        #    - org.planid → resolved from price_id via catalog lookup
        #    - org.subscription_status → updated from subscription.status
        #    - org.stripe_subscription_id → verified/updated
        #
        # 3. FRONTEND STATE (Pinia stores)
        #    - organizationStore.planid → refreshed via fetchOrganizations()
        #    - currentTier → computed from org.planid matching plans[].id
        #
        # NOTE: With catalog-first design, the authoritative plan_id is resolved from
        # price_id via Billing::PlanValidator.resolve_plan_id. Metadata is stored for
        # debugging and drift detection only - stale metadata is logged but doesn't
        # affect the resolved plan_id.
        #
        # ==========================================================================

        # Get the new plan details for metadata update
        # Plan lookup: new_price_id → Billing::Plan cache → plan.plan_id, plan.tier
        new_plan = ::Billing::Plan.find_by_stripe_price_id(new_price_id)

        # Execute the plan change with synchronized metadata
        updated_subscription = Stripe::Subscription.update(
          org.stripe_subscription_id,
          {
            items: [{
              id: current_item.id,
              price: new_price_id,
            }],
            proration_behavior: 'create_prorations',
            # Metadata stored for debugging/drift detection (catalog is authoritative)
            metadata: {
              plan_id: new_plan&.plan_id,
              tier: new_plan&.tier,
            },
          },
          { idempotency_key: idempotency_key },
        )

        # Propagate to local storage: Stripe → Organization model (Redis)
        # This calls extract_plan_id_from_subscription which resolves plan_id from
        # price_id via catalog lookup, then sets org.planid and saves to Redis.
        #
        # STATE SYNC: Stripe is authoritative. If local update fails, the Stripe
        # change already succeeded (billing is correct). We log the sync failure
        # and return success; webhooks will reconcile state eventually.
        local_sync_failed = false
        begin
          org.update_from_stripe_subscription(updated_subscription)
        rescue StandardError => sync_ex
          local_sync_failed = true
          billing_logger.error 'Local state sync failed after Stripe update', {
            extid: org.extid,
            stripe_subscription_id: updated_subscription.id,
            new_price_id: new_price_id,
            error_class: sync_ex.class.name,
            error_message: sync_ex.message,
            idempotency_key: idempotency_key[0..7],
            recovery: 'webhook_reconciliation',
          }
        end

        billing_logger.info 'Plan changed successfully', {
          extid: org.extid,
          old_price_id: current_item.price.id,
          new_price_id: new_price_id,
          new_plan: local_sync_failed ? new_plan&.plan_id : org.planid,
          local_sync_failed: local_sync_failed,
          idempotency_key: idempotency_key[0..7], # Log prefix for debugging
        }

        json_response({
          success: true,
          new_plan: local_sync_failed ? new_plan&.plan_id : org.planid,
          status: updated_subscription.status,
          current_period_end: updated_subscription.items.data.first.current_period_end,
        },
                     )
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

      module PrivateMethods
        private

        # Check if invoice line item is a proration
        #
        # In Stripe API 2023+, proration status moved to parent details.
        # Checks both invoice_item_details and subscription_item_details.
        #
        # @param line [Stripe::InvoiceLineItem] Invoice line item
        # @return [Boolean] True if line is a proration
        def line_is_proration?(line)
          parent = line.parent
          return false unless parent

          # Check both possible parent types for proration flag
          parent.invoice_item_details&.proration ||
            parent.subscription_item_details&.proration ||
            false
        end

        # Validate plan change request parameters
        #
        # Checks common validation rules for plan change operations.
        # Returns [true, nil] if valid, [false, error_response] if invalid.
        #
        # @param org [Onetime::Organization] Organization instance
        # @param new_price_id [String, nil] Stripe price ID to switch to
        # @return [Array<(Boolean, Object)>] [valid?, error_response_or_nil]
        def validate_plan_change_request(org, new_price_id)
          # Guard: missing new_price_id
          unless new_price_id
            return [false, json_error('Missing new_price_id', status: 400)]
          end

          # Guard: no active subscription
          unless org.active_subscription?
            return [false, json_error('No active subscription to modify', status: 400)]
          end

          [true, nil]
        end

        # Validate target plan is valid (in catalog and not legacy)
        #
        # Called AFTER same-plan check to maintain proper error ordering.
        #
        # @param new_price_id [String] Stripe price ID to switch to
        # @return [Array<(Boolean, Object)>] [valid?, error_response_or_nil]
        def validate_target_plan(new_price_id)
          # Guard: unknown price ID (not in our plan catalog)
          target_plan_id = price_id_to_plan_id(new_price_id)
          if target_plan_id.nil?
            return [false, json_error('Invalid price ID', status: 400)]
          end

          # Guard: legacy plan
          if Billing::PlanHelpers.legacy_plan?(target_plan_id)
            return [false, json_error('This plan is not available', status: 400)]
          end

          [true, nil]
        end

        # Convert Stripe price ID to plan ID
        #
        # Looks up the plan associated with a Stripe price ID using cached lookup.
        #
        # @param price_id [String] Stripe price ID
        # @return [String, nil] Plan ID or nil if not found
        def price_id_to_plan_id(price_id)
          ::Billing::Plan.find_by_stripe_price_id(price_id)&.plan_id
        end

        # Calculate proration amounts from invoice preview
        #
        # @param preview [Stripe::Invoice] Invoice preview object
        # @return [Hash] Proration breakdown with credit_applied, immediate_amount, next_period_amount
        def calculate_proration_amounts(preview)
          proration_lines = preview.lines.data.select { |line| line_is_proration?(line) }
          regular_lines   = preview.lines.data.reject { |line| line_is_proration?(line) }

          {
            credit_applied: proration_lines.select { |l| l.amount.negative? }.sum(&:amount).abs,
            immediate_amount: proration_lines.sum(&:amount),
            next_period_amount: regular_lines.sum(&:amount),
          }
        end

        # Find price object from invoice preview lines
        #
        # @param preview [Stripe::Invoice] Invoice preview object
        # @param target_price_id [String] Price ID to find
        # @return [Stripe::Price, nil] Price object or nil
        def find_price_in_preview(preview, target_price_id)
          price = preview.lines.data
            .map { |line| line.pricing&.price_details&.price || line.price }
            .compact
            .find { |p| (p.is_a?(String) ? p : p.id) == target_price_id }

          # Fetch full price object if we got a string or nothing
          price.is_a?(String) || price.nil? ? Stripe::Price.retrieve(target_price_id) : price
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

      include PrivateMethods
    end
  end
end
