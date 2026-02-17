# apps/web/billing/controllers/billing.rb
#
# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength

require 'stripe'

require_relative 'base'
require_relative '../lib/stripe_client'
require_relative '../lib/currency_migration_service'

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

        # Include federation notification when org is federated and not dismissed
        if org.show_federation_notification?
          data[:federation_notification] = {
            show: true,
            source_region: region,
          }
        end

        json_response(data)
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue StandardError => ex
        billing_logger.error 'Failed to load billing overview',
          {
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
      # @param [String] product Plan product identifier (e.g., 'identity_plus_v1')
      # @param [String] interval Billing interval ('monthly' or 'yearly')
      #
      # @return [Hash] Checkout session URL
      def create_checkout_session
        org = load_organization(req.params['extid'], require_owner: true)

        product  = req.params['product']
        interval = req.params['interval']

        unless product && interval
          return json_error('Missing product or interval', status: 400)
        end

        # Resolve plan from product + interval
        result = ::Billing::PlanResolver.resolve(product: product, interval: interval)

        unless result.success?
          billing_logger.warn 'Plan resolution failed',
            {
              product: product,
              interval: interval,
              error: result.error,
            }
          return json_error(result.error, status: 400)
        end

        # Get the resolved plan
        plan = result.plan || ::Billing::Plan.load(result.plan_id)

        unless plan
          billing_logger.warn 'Plan not found after resolution',
            {
              product: product,
              interval: interval,
              plan_id: result.plan_id,
            }
          return json_error('Plan not found', status: 404)
        end

        # Build checkout session parameters
        site_host = Onetime.conf['site']['host']
        is_secure = Onetime.conf['site']['ssl']
        protocol  = is_secure ? 'https' : 'http'

        success_url = "#{protocol}://#{site_host}/billing/welcome?session_id={CHECKOUT_SESSION_ID}"
        cancel_url  = "#{protocol}://#{site_host}/billing/#{org.extid}/plans"

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
              tier: result.tier,
              region: detect_region,
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

        billing_logger.info 'Checkout session created for organization',
          {
            extid: org.extid,  # Use extid for logging, not objid
            session_id: checkout_session.id,
            product: product,
            interval: interval,
            idempotency_key: idempotency_key[0..7], # Log prefix for debugging
          }

        json_response(
          {
            checkout_url: checkout_session.url,
            session_id: checkout_session.id,
          },
        )
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue Stripe::InvalidRequestError => ex
        if Billing::CurrencyMigrationService.currency_conflict?(ex)
          currencies = Billing::CurrencyMigrationService.parse_currency_conflict(ex)

          billing_logger.info 'Currency conflict detected during checkout',
            {
              extid: req.params['extid'],
              existing_currency: currencies[:existing_currency],
              requested_currency: currencies[:requested_currency],
            }

          # Build detailed assessment for the frontend migration prompt.
          # Wrap in rescue since assess_migration makes Stripe API calls
          # that could raise inside this outer rescue block.
          begin
            assessment = Billing::CurrencyMigrationService.assess_migration(
              org,
              currencies[:existing_currency],
              currencies[:requested_currency],
              plan.stripe_price_id,
            )
          rescue Stripe::StripeError => assess_ex
            billing_logger.error 'Failed to assess migration during currency conflict',
              { exception: assess_ex, extid: req.params['extid'] }
            assessment = { current_plan: nil, requested_plan: nil, warnings: {} }
          end

          json_response(
            {
              error: true,
              code: 'currency_conflict',
              details: {
                existing_currency: currencies[:existing_currency],
                requested_currency: currencies[:requested_currency],
                current_plan: assessment[:current_plan],
                requested_plan: assessment[:requested_plan],
                warnings: assessment[:warnings],
              },
            },
            status: 409,
          )
        else
          billing_logger.error 'Stripe checkout session creation failed',
            {
              exception: ex,
              extid: req.params['extid'],
            }
          json_error(ex.message, status: 400)
        end
      rescue Stripe::StripeError => ex
        billing_logger.error 'Stripe checkout session creation failed',
          {
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
        invoices = Stripe::Invoice.list(
          {
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

        json_response(
          {
            invoices: invoice_data,
            has_more: invoices.has_more,
          },
        )
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue Stripe::StripeError => ex
        billing_logger.error 'Failed to retrieve invoices',
          {
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
        plans = ::Billing::Plan.list_plans.compact

        # Build lookup for resolving includes_plan_name
        # Plan IDs include interval suffix (e.g., "identity_v1_monthly"), but includes_plan
        # references the base ID (e.g., "identity_v1"). Map both for flexibility.
        plan_names_by_id = plans.each_with_object({}) do |plan, lookup|
          lookup[plan.plan_id] = plan.name
          # Also index by base ID (strip interval suffix)
          base_id              = plan.plan_id.sub(/_(month|year)ly$/, '')
          lookup[base_id]      = plan.name
        end

        # Filter by show_on_plans_page and sort by display_order (ascending - lower values first)
        plan_data = plans
          .select { |plan| plan.show_on_plans_page.to_s == 'true' }
          .map do |plan|
            {
              id: plan.plan_id,
              stripe_price_id: plan.stripe_price_id,  # nil for free/config-only plans
              name: plan.name,
              tier: plan.tier,
              interval: plan.interval,
              amount: plan.amount,
              currency: plan.currency,
              features: plan.features.to_a,
              limits: plan.limits_hash.transform_values { |v| v == Float::INFINITY ? -1 : v },
              entitlements: plan.entitlements.to_a,
              display_order: plan.display_order.to_i,
              plan_code: plan.plan_code,
              is_popular: plan.popular?,
              plan_name_label: plan.plan_name_label,
              includes_plan: plan.includes_plan,
              includes_plan_name: plan_names_by_id[plan.includes_plan],
            }
          end
          .sort_by { |p| p[:display_order] } # Ascending: Free (0) → Identity Plus (10) → Org Max (40)

        json_response({ plans: plan_data })
      rescue StandardError => ex
        billing_logger.error 'Failed to list plans',
          {
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
          data = {
            has_active_subscription: false,
            current_plan: org.planid,
          }

          # Include pending migration info if present
          if org.pending_currency_migration?
            data[:pending_currency_migration] = pending_migration_data(org)
          end

          return json_response(data)
        end

        # Validate Stripe API key is configured before making API calls
        if stripe_api_key_missing?('subscription_status')
          return json_error('Billing service temporarily unavailable', status: 503)
        end

        # Fetch current subscription from Stripe
        subscription = Stripe::Subscription.retrieve(org.stripe_subscription_id)
        current_item = subscription.items.data.first

        data = {
          has_active_subscription: true,
          current_plan: org.planid,
          current_price_id: current_item.price.id,
          current_currency: subscription.currency,
          subscription_item_id: current_item.id,
          subscription_status: subscription.status,
          current_period_end: current_item.current_period_end,
          cancel_at_period_end: subscription.cancel_at_period_end,
          cancel_at: subscription.cancel_at,
        }

        # Include pending migration info if present
        if org.pending_currency_migration?
          data[:pending_currency_migration] = pending_migration_data(org)
        end

        json_response(data)
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue Stripe::StripeError => ex
        billing_logger.error 'Failed to retrieve subscription status',
          {
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

        # Check for currency mismatch before calling Stripe
        conflict_response = check_currency_conflict(org, new_price_id)
        return conflict_response if conflict_response

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

        # Calculate convenience fields for frontend credit display
        #
        # For downgrades: immediate_amount is negative (net credit from proration)
        # This credit goes to customer balance and applies to future invoices
        #
        # Example: Downgrade from $99 to $35 mid-cycle
        #   - credit_applied: $133.91 (unused time on old plan)
        #   - immediate_amount: -$98.91 (net credit after new plan proration)
        #   - next_period_amount: $35.00 (next full month on new plan)
        #   - proration_credit_to_balance: $98.91
        #   - actual_next_billing_due: max(0, $35 - $98.91) = $0
        #   - remaining_credit: max(0, $98.91 - $35) = $63.91
        #
        proration_credit_to_balance = amounts[:immediate_amount].negative? ? amounts[:immediate_amount].abs : 0
        actual_next_billing_due     = [amounts[:next_period_amount] - proration_credit_to_balance, 0].max
        remaining_credit            = [proration_credit_to_balance - amounts[:next_period_amount], 0].max

        # Also capture Stripe's ending_balance if available (may be nil for previews)
        ending_balance = preview.ending_balance || 0

        json_response(
          {
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
            # Credit breakdown fields for clearer frontend display
            ending_balance: ending_balance,           # Negative = credit remaining after invoice
            tax: extract_tax_amount(preview),         # Tax amount on this invoice (if available)
            remaining_credit: remaining_credit,        # Absolute value of credit if ending_balance negative
            actual_next_billing_due: actual_next_billing_due, # What they'll actually pay at next billing
          },
        )
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue Stripe::InvalidRequestError => ex
        billing_logger.warn 'Invalid plan change preview request',
          {
            exception: ex,
            extid: req.params['extid'],
            new_price_id: new_price_id,
          }
        json_error(ex.message, status: 400)
      rescue Stripe::StripeError => ex
        billing_logger.error 'Failed to preview plan change',
          {
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

        # Check for currency mismatch before calling Stripe
        conflict_response = check_currency_conflict(org, new_price_id)
        return conflict_response if conflict_response

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
        # If subscription was scheduled for cancellation, reactivate it by clearing
        # cancel_at_period_end. A plan change implies the user wants to continue.
        updated_subscription = Stripe::Subscription.update(
          org.stripe_subscription_id,
          {
            items: [{
              id: current_item.id,
              price: new_price_id,
            }],
            proration_behavior: 'create_prorations',
            # Clear cancellation flag if subscription was scheduled for cancellation.
            # Changing plans indicates intent to continue - reactivate the subscription.
            cancel_at_period_end: false,
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
        rescue StandardError => ex
          local_sync_failed = true
          billing_logger.error 'Local state sync failed after Stripe update',
            {
              extid: org.extid,
              stripe_subscription_id: updated_subscription.id,
              new_price_id: new_price_id,
              error_class: ex.class.name,
              error_message: ex.message,
              idempotency_key: idempotency_key[0..7],
              recovery: 'webhook_reconciliation',
            }
        end

        billing_logger.info 'Plan changed successfully',
          {
            extid: org.extid,
            old_price_id: current_item.price.id,
            new_price_id: new_price_id,
            new_plan: local_sync_failed ? new_plan&.plan_id : org.planid,
            local_sync_failed: local_sync_failed,
            idempotency_key: idempotency_key[0..7], # Log prefix for debugging
          }

        json_response(
          {
            success: true,
            new_plan: local_sync_failed ? new_plan&.plan_id : org.planid,
            status: updated_subscription.status,
            current_period_end: updated_subscription.items.data.first.current_period_end,
          },
        )
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue Stripe::InvalidRequestError => ex
        billing_logger.warn 'Invalid plan change request',
          {
            exception: ex,
            extid: req.params['extid'],
            new_price_id: new_price_id,
          }
        json_error(ex.message, status: 400)
      rescue Stripe::StripeError => ex
        billing_logger.error 'Failed to change plan',
          {
            exception: ex,
            extid: req.params['extid'],
          }
        json_error('Failed to change plan', status: 500)
      end

      # Dismiss federation notification
      #
      # Records that the user has dismissed the federation notification.
      # The notification won't be shown again until subscription_federated_at
      # is updated (new federation event).
      #
      # POST /billing/api/org/:extid/dismiss-federation-notification
      #
      # @return [Hash] Success response
      def dismiss_federation_notification
        org = load_organization(req.params['extid'])

        org.dismiss_federation_notification!
        org.save

        billing_logger.info 'Federation notification dismissed',
          {
            orgid: org.objid,
            extid: org.extid,
          }

        json_response({ success: true })
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue StandardError => ex
        billing_logger.error 'Failed to dismiss federation notification',
          {
            exception: ex,
            extid: req.params['extid'],
          }
        json_error('Failed to dismiss notification', status: 500)
      end

      # Cancel subscription at period end
      #
      # Schedules the organization's subscription for cancellation at the end
      # of the current billing period. Uses cancel_at_period_end: true so the
      # customer retains access until their paid period expires.
      #
      # POST /billing/api/org/:extid/cancel-subscription
      #
      # @return [Hash] Result with cancel_at timestamp and status
      def cancel_subscription
        org = load_organization(req.params['extid'], require_owner: true)

        unless org.active_subscription?
          return json_error('No active subscription to cancel', status: 400)
        end

        unless org.stripe_subscription_id
          return json_error('No Stripe subscription found', status: 400)
        end

        if stripe_api_key_missing?('cancel_subscription')
          return json_error('Billing service temporarily unavailable', status: 503)
        end

        # Cancel at period end (standard SaaS pattern - customer keeps access until paid period ends)
        canceled_subscription = Stripe::Subscription.update(
          org.stripe_subscription_id,
          { cancel_at_period_end: true },
        )

        # Get the period end from subscription item (Stripe API 2025-11-17.clover)
        first_item = canceled_subscription.items&.data&.first
        cancel_at  = first_item&.current_period_end

        billing_logger.info 'Subscription cancellation scheduled',
          {
            extid: org.extid,
            subscription_id: canceled_subscription.id,
            cancel_at: cancel_at,
            status: canceled_subscription.status,
          }

        json_response(
          {
            success: true,
            cancel_at: cancel_at,
            status: canceled_subscription.status,
          },
        )
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue Stripe::InvalidRequestError => ex
        billing_logger.warn 'Invalid subscription cancellation request',
          {
            exception: ex,
            extid: req.params['extid'],
          }
        json_error(ex.message, status: 400)
      rescue Stripe::StripeError => ex
        billing_logger.error 'Failed to cancel subscription',
          {
            exception: ex,
            extid: req.params['extid'],
          }
        json_error('Failed to cancel subscription', status: 500)
      end

      # Pre-check for currency mismatch
      #
      # Detects currency mismatch between current subscription and target plan
      # *before* hitting Stripe. This avoids relying on the Stripe error as the
      # primary detection mechanism.
      #
      # POST /billing/api/org/:extid/check-currency-migration
      #
      # @param [String] target_price_id Stripe price ID to check against
      #
      # @return [Hash] Mismatch details or confirmation that currencies match
      def check_currency_migration
        org = load_organization(req.params['extid'])

        target_price_id = req.params['target_price_id']
        unless target_price_id
          return json_error('Missing target_price_id', status: 400)
        end

        unless org.stripe_customer_id
          return json_error('No Stripe customer linked to this organization', status: 400)
        end

        if stripe_api_key_missing?('check_currency_migration')
          return json_error('Billing service temporarily unavailable', status: 503)
        end

        mismatch = Billing::CurrencyMigrationService.check_currency_mismatch(org, target_price_id)

        if mismatch
          # Currency mismatch found — return full assessment
          assessment = Billing::CurrencyMigrationService.assess_migration(
            org,
            mismatch[:existing_currency],
            mismatch[:requested_currency],
            target_price_id,
          )

          billing_logger.info 'Currency mismatch detected (pre-check)',
            {
              extid: org.extid,
              existing_currency: mismatch[:existing_currency],
              requested_currency: mismatch[:requested_currency],
            }

          json_response(
            {
              currency_mismatch: true,
              details: {
                existing_currency: mismatch[:existing_currency],
                requested_currency: mismatch[:requested_currency],
                current_plan: assessment[:current_plan],
                requested_plan: assessment[:requested_plan],
                warnings: assessment[:warnings],
                can_migrate: assessment[:can_migrate],
                blockers: assessment[:blockers],
              },
            },
          )
        else
          json_response({ currency_mismatch: false })
        end
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue Stripe::StripeError => ex
        billing_logger.error 'Currency migration check failed',
          {
            exception: ex,
            extid: req.params['extid'],
          }
        json_error('Failed to check currency migration', status: 500)
      end

      # Execute currency migration
      #
      # Performs the actual currency migration using either the graceful
      # or immediate path.
      #
      # POST /billing/api/org/:extid/migrate-currency
      #
      # @param [String] new_price_id Stripe price ID for the target plan
      # @param [String] mode 'graceful' or 'immediate'
      #
      # @return [Hash] Migration result
      def migrate_currency
        org = load_organization(req.params['extid'], require_owner: true)

        new_price_id = req.params['new_price_id']
        mode         = req.params['mode']

        unless new_price_id && mode
          return json_error('Missing new_price_id or mode', status: 400)
        end

        unless %w[graceful immediate].include?(mode)
          return json_error('mode must be "graceful" or "immediate"', status: 400)
        end

        unless org.stripe_customer_id
          return json_error('No Stripe customer linked to this organization', status: 400)
        end

        # Validate target plan exists in catalog
        target_plan = ::Billing::Plan.find_by_stripe_price_id(new_price_id)
        unless target_plan
          return json_error('Invalid price ID — plan not found in catalog', status: 400)
        end

        if stripe_api_key_missing?('migrate_currency')
          return json_error('Billing service temporarily unavailable', status: 503)
        end

        # Check for past_due subscription (blocker for all migration types)
        if org.past_due?
          return json_response(
            {
              error: true,
              code: 'migration_blocked',
              message: 'Your subscription has an overdue payment. Please resolve the payment before migrating currencies.',
            },
            status: 409,
          )
        end

        result = case mode
        when 'graceful'
          unless org.stripe_subscription_id
            return json_error('No active subscription for graceful migration', status: 400)
          end

          Billing::CurrencyMigrationService.execute_graceful_migration(org, new_price_id)
        when 'immediate'
          site_host = Onetime.conf['site']['host']
          is_secure = Onetime.conf['site']['ssl']
          protocol  = is_secure ? 'https' : 'http'

          success_url = "#{protocol}://#{site_host}/billing/welcome?session_id={CHECKOUT_SESSION_ID}"
          cancel_url  = "#{protocol}://#{site_host}/billing/#{org.extid}/plans"

          Billing::CurrencyMigrationService.execute_immediate_migration(
            org,
            new_price_id,
            success_url: success_url,
            cancel_url: cancel_url,
          )
        end

        billing_logger.info 'Currency migration executed',
          {
            extid: org.extid,
            mode: mode,
            new_price_id: new_price_id,
            success: result[:success],
          }

        json_response(result)
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue Stripe::InvalidRequestError => ex
        billing_logger.warn 'Currency migration request failed',
          {
            exception: ex,
            extid: req.params['extid'],
            mode: mode,
          }
        json_error(ex.message, status: 400)
      rescue Stripe::StripeError => ex
        billing_logger.error 'Currency migration execution failed',
          {
            exception: ex,
            extid: req.params['extid'],
          }
        json_error('Failed to execute currency migration', status: 500)
      end

      module PrivateMethods
        private

        # Check for currency mismatch and return a 409 response if found.
        #
        # @param org [Onetime::Organization] Organization to check
        # @param new_price_id [String] Target Stripe Price ID
        # @return [Object, nil] JSON error response if conflict, nil otherwise
        def check_currency_conflict(org, new_price_id)
          mismatch = Billing::CurrencyMigrationService.check_currency_mismatch(org, new_price_id)
          return nil unless mismatch

          json_response(
            {
              error: true,
              code: 'currency_conflict',
              existing_currency: mismatch[:existing_currency],
              requested_currency: mismatch[:requested_currency],
            },
            status: 409,
          )
        end

        # Build pending migration data hash for subscription_status response
        #
        # Resolves plan name and currency from the stored target_price_id so
        # the frontend PendingMigrationBanner has all the data it needs.
        #
        # @param org [Onetime::Organization] Organization with pending migration
        # @return [Hash] Migration data matching pendingMigrationSchema
        def pending_migration_data(org)
          price_id = org.migration_target_price_id
          plan     = ::Billing::Plan.find_by_stripe_price_id(price_id)

          {
            target_price_id: price_id,
            target_plan_name: plan&.name || 'Unknown',
            target_currency: plan&.currency || 'unknown',
            target_plan_id: plan&.plan_id,
            effective_after: org.migration_effective_after.to_i,
          }
        end

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

        # Extract tax amount from invoice preview
        # Handles Stripe API version changes (total_tax_amounts → total_taxes in 2025-03-31)
        #
        # @param preview [Stripe::Invoice] Invoice preview object
        # @return [Integer] Tax amount in cents, or 0 if not available
        def extract_tax_amount(preview)
          # New API (2025-03-31+): total_taxes
          if preview.respond_to?(:total_taxes) && preview.total_taxes&.any?
            return preview.total_taxes.sum { |t| t.amount }
          end

          # Legacy API: total_tax_amounts (deprecated but may still be present)
          if preview.respond_to?(:total_tax_amounts) && preview.total_tax_amounts&.any?
            return preview.total_tax_amounts.sum { |t| t.amount }
          end

          # Fallback: calculate from total - subtotal_excluding_tax (most reliable)
          if preview.respond_to?(:total) && preview.respond_to?(:subtotal_excluding_tax)
            subtotal_ex_tax = preview.subtotal_excluding_tax || preview.subtotal || 0
            tax_diff        = (preview.total || 0) - subtotal_ex_tax
            return tax_diff if tax_diff.positive?
          end

          # No tax info available
          0
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
