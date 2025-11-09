# apps/web/billing/controllers/billing.rb

require_relative 'base'
require 'stripe'

module Billing
  module Controllers
    class Billing
      include Controllers::Base

      # Get billing overview for organization
      #
      # Returns current subscription status, plan details, and usage information.
      #
      # GET /billing/org/:ext_id
      #
      # @return [Hash] Billing overview data
      def overview
        org = load_organization(req.params['org_id'])

        data = {
          organization: {
            id: org.orgid,
            external_id: org.extid,
            display_name: org.display_name,
            billing_email: org.billing_email
          },
          subscription: build_subscription_data(org),
          plan: build_plan_data(org),
          usage: build_usage_data(org)
        }

        json_response(data)
      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue StandardError => ex
        billing_logger.error "Failed to load billing overview", {
          exception: ex,
          ext_id: req.params[:ext_id]
        }
        json_error("Failed to load billing data", status: 500)
      end

      # Create checkout session for organization
      #
      # Creates a new Stripe Checkout Session for the organization to subscribe
      # or change their plan.
      #
      # POST /billing/org/:ext_id/checkout
      #
      # @param [String] tier Plan tier (from request body)
      # @param [String] billing_cycle Billing cycle (from request body)
      #
      # @return [Hash] Checkout session URL
      def create_checkout_session
        org = load_organization(req.params[:org_id], require_owner: true)

        tier = req.params['tier']
        billing_cycle = req.params['billing_cycle']

        unless tier && billing_cycle
          return json_error("Missing tier or billing_cycle", status: 400)
        end

        # Detect region
        region = detect_region

        # Get plan from cache
        plan = Billing::Models::PlanCache.get_plan(tier, billing_cycle, region)

        unless plan
          billing_logger.warn "Plan not found", {
            tier: tier,
            billing_cycle: billing_cycle,
            region: region
          }
          return json_error("Plan not found", status: 404)
        end

        # Build checkout session parameters
        site_host = Onetime.conf['site']['host']
        is_secure = Onetime.conf['site']['ssl']
        protocol = is_secure ? 'https' : 'http'

        success_url = "#{protocol}://#{site_host}/billing/welcome?session_id={CHECKOUT_SESSION_ID}"
        cancel_url = "#{protocol}://#{site_host}/account"

        session_params = {
          mode: 'subscription',
          line_items: [{
            price: plan.stripe_price_id,
            quantity: 1
          }],
          success_url: success_url,
          cancel_url: cancel_url,
          customer_email: org.billing_email || cust.email,
          client_reference_id: org.orgid,
          locale: req.env['rack.locale']&.first || 'auto',
          subscription_data: {
            metadata: {
              orgid: org.orgid,
              plan_id: plan.plan_id,
              tier: tier,
              region: region,
              custid: cust.custid
            }
          }
        }

        # If organization already has a Stripe customer, use it
        if org.stripe_customer_id
          session_params[:customer] = org.stripe_customer_id
          session_params.delete(:customer_email)
        end

        # Create Stripe Checkout Session
        checkout_session = Stripe::Checkout::Session.create(session_params)

        billing_logger.info "Checkout session created for organization", {
          orgid: org.orgid,
          session_id: checkout_session.id,
          tier: tier,
          billing_cycle: billing_cycle
        }

        json_response({
          checkout_url: checkout_session.url,
          session_id: checkout_session.id
        })

      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue Stripe::StripeError => ex
        billing_logger.error "Stripe checkout session creation failed", {
          exception: ex,
          ext_id: req.params[:ext_id]
        }
        json_error("Failed to create checkout session", status: 500)
      end

      # List invoices for organization
      #
      # Returns recent invoices from Stripe for the organization's customer.
      #
      # GET /billing/org/:ext_id/invoices
      #
      # @return [Hash] List of invoices
      def list_invoices
        org = load_organization(req.params[:ext_id])

        unless org.stripe_customer_id
          return json_response({ invoices: [] })
        end

        # Retrieve invoices from Stripe
        invoices = Stripe::Invoice.list({
          customer: org.stripe_customer_id,
          limit: 12 # Last 12 invoices
        })

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
            hosted_invoice_url: invoice.hosted_invoice_url
          }
        end

        json_response({
          invoices: invoice_data,
          has_more: invoices.has_more
        })

      rescue OT::Problem => ex
        json_error(ex.message, status: 403)
      rescue Stripe::StripeError => ex
        billing_logger.error "Failed to retrieve invoices", {
          exception: ex,
          ext_id: req.params[:ext_id]
        }
        json_error("Failed to retrieve invoices", status: 500)
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
          canceled: org.canceled?
        }
      end

      # Build plan data for response
      #
      # @param org [Onetime::Organization] Organization instance
      # @return [Hash, nil] Plan data or nil if no plan
      def build_plan_data(org)
        return nil unless org.planid

        plan = Billing::Models::PlanCache.load(org.planid)
        return nil unless plan

        {
          id: plan.plan_id,
          name: plan.name,
          tier: plan.tier,
          interval: plan.interval,
          amount: plan.amount,
          currency: plan.currency,
          features: plan.parsed_features,
          limits: plan.parsed_limits
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
          members: org.members.size
        }
      end


    end
  end
end
