# apps/web/billing/controllers/billing.rb
#
# frozen_string_literal: true

require 'stripe'

require_relative 'base'
require_relative '../lib/stripe_client'

module Billing
  module Controllers
    class Billing
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
              custid: cust.custid,
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

        # Idempotency key format: checkout-{orgid}-{plan}-{date}
        # This allows one checkout per org/plan/day, preventing duplicates
        # SHA256 produces 64 hex chars, well within Stripe's 255 char limit
        idempotency_key = Digest::SHA256.hexdigest(
          "checkout:#{org.objid}:#{plan.plan_id}:#{Time.now.to_date.iso8601}",
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

        # Filter out nil plans (stale cache entries)
        plan_data = plans.compact.map do |plan|
          {
            id: plan.plan_id,
            name: plan.name,
            tier: plan.tier,
            interval: plan.interval,
            amount: plan.amount,
            currency: plan.currency,
            region: plan.region,
            features: plan.features.to_a,
            limits: plan.limits_hash,
            capabilities: plan.capabilities.to_a,
          }
        end

        json_response({ plans: plan_data })
      rescue StandardError => ex
        billing_logger.error 'Failed to list plans', {
          exception: ex,
        }
        json_error('Failed to list plans', status: 500)
      end

      private

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
        # Phase 1: Basic team/member counts
        # Future: Add secret counts, API usage, etc.
        {
          teams: org.teams.size,
          members: org.members.size,
        }
      end
    end
  end
end
