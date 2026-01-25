# apps/web/billing/controllers/plans.rb
#
# frozen_string_literal: true

require_relative 'base'
require 'stripe'

module Billing
  module Controllers
    class Plans
      include Controllers::Base

      # Dynamic checkout session creation with region detection
      #
      # Replaces static Stripe Payment Links with dynamic Checkout Sessions
      # that include organization metadata.
      #
      # ## Checkout Session Features
      #
      # - Automatic Tax: Stripe Tax for EU VAT, Canadian GST/HST, etc.
      # - VAT ID Collection: EU B2B customers can enter VAT for reverse charge
      # - Idempotency Key: Per-customer, per-plan, per-minute to prevent duplicates
      # - Nested JSON Metadata: Grouped debug info per Stripe best practices
      # - Customer Reuse: Returning subscribers use existing Stripe Customer ID
      #
      # GET /billing/plans/:product/:interval
      #
      # @param [String] product The plan product ID (e.g., 'identity_plus_v1')
      # @param [String] interval The billing interval ('monthly', 'yearly')
      #
      # @return [HTTP 302] Redirects to Stripe Checkout Session
      #
      def checkout_redirect
        product  = req.params['product']
        interval = req.params['interval']

        # Detect region from request (future: use GeoIP)
        region = detect_region

        billing_logger.debug 'Plan checkout request',
          {
            product: product,
            interval: interval,
            region: region,
          }

        # Resolve plan from product + interval
        result = ::Billing::PlanResolver.resolve(product: product, interval: interval)

        unless result.success?
          billing_logger.warn 'Plan resolution failed',
            {
              product: product,
              interval: interval,
              error: result.error,
            }
          res.redirect '/signup'
          return
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
          res.redirect '/signup'
          return
        end

        # Build checkout session parameters
        site_host = Onetime.conf['site']['host']
        is_secure = Onetime.conf['site']['ssl']
        protocol  = is_secure ? 'https' : 'http'

        success_url = "#{protocol}://#{site_host}/billing/welcome?session_id={CHECKOUT_SESSION_ID}"
        cancel_url  = "#{protocol}://#{site_host}/plans"

        session_params = {
          mode: 'subscription',
          line_items: [{
            price: plan.stripe_price_id,
            quantity: 1,
          }],
          success_url: success_url,
          cancel_url: cancel_url,
          locale: req.env['rack.locale']&.first || 'auto',

          # Stripe Tax: automatic tax calculation for all regions
          #
          # How tax works:
          # - EU Customers: Can enter VAT number → reverse charge applied automatically
          # - Canadian Customers: GST/HST calculated based on province
          # - Other Regions: Stripe Tax calculates per Dashboard configuration
          #
          # Dashboard prerequisites (Settings → Tax):
          # 1. Stripe Tax enabled
          # 2. Tax registrations added for applicable jurisdictions
          # 3. Products have appropriate tax codes (or default tax code set)
          #
          automatic_tax: { enabled: true },
          tax_id_collection: { enabled: true },  # EU B2B VAT reverse charge
        }

        # Customer handling for authenticated users
        # Reuse existing Stripe Customer if the user has an org with one (returning subscriber)
        # Otherwise, Stripe creates a new customer from email prefill
        unless cust.anonymous?
          session_params[:client_reference_id] = cust.extid

          # Check for existing Stripe customer on user's default organization
          default_org = cust.organization_instances.to_a.find(&:is_default)
          if default_org&.stripe_customer_id.to_s.length.positive?
            session_params[:customer] = default_org.stripe_customer_id
          else
            session_params[:customer_email] = cust.email
          end
        end

        # Subscription metadata for webhook processing and debugging
        #
        # NOTE: plan_id is stored as debug_info only. The authoritative plan_id
        # is resolved from price_id via catalog lookup in webhook processing.
        # This metadata is useful for debugging subscription creation but should
        # NOT be relied upon for billing decisions.
        #
        # JSON in metadata: Stripe explicitly recommends storing structured data
        # as JSON strings in metadata values (up to 500 chars). This approach
        # reduces key usage (Stripe has a 50-key limit) and groups related info.
        # @see https://docs.stripe.com/metadata/use-cases#store-structured-data
        #
        # @see Billing::PlanValidator.resolve_plan_id
        # @see WithOrganizationBilling#extract_plan_id_from_subscription
        #
        session_params[:subscription_data] = {
          metadata: {
            debug_info: {
              checkout_plan_id: plan.plan_id,
              checkout_tier: result.tier,
              checkout_region: region,
              checkout_timestamp: Time.now.iso8601,
            }.to_json,
            customer_extid: cust.extid,
          },
        }

        # Create Stripe Checkout Session with idempotency key
        # Key granularity: per-customer, per-plan, per-minute (prevents duplicates on retry)
        idempotency_key  = "checkout_#{cust.extid}_#{plan.plan_id}_#{Time.now.to_i / 60}"
        checkout_session = Stripe::Checkout::Session.create(
          session_params,
          { idempotency_key: idempotency_key },
        )

        billing_logger.info 'Checkout session created',
          {
            session_id: checkout_session.id,
            product: product,
            interval: interval,
            region: region,
          }

        res.redirect checkout_session.url
      rescue Stripe::StripeError => ex
        billing_logger.error 'Stripe checkout session creation failed',
          {
            exception: ex,
            product: product,
            interval: interval,
          }
        res.redirect '/signup'
      end

      # Welcome page after successful Stripe checkout
      #
      # Processes the checkout session and sets up the organization subscription.
      #
      # GET /billing/welcome?session_id={CHECKOUT_SESSION_ID}
      #
      # @see Billing::Logic::Welcome::ProcessCheckoutSession
      #
      def welcome
        logic  = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, req.params, locale)
        logic.raise_concerns
        result = logic.process

        # Redirect to the billing overview for the upgraded organization
        # This provides clear feedback about the successful purchase
        org_extid = result[:org_extid]
        if org_extid
          res.redirect "/billing/#{org_extid}/overview?upgraded=true"
        else
          # Fallback for one-time payments or missing org context
          res.redirect '/account'
        end
      rescue Onetime::FormError => ex
        billing_logger.warn 'Welcome page validation failed',
          {
            error: ex.message,
            session_id: req.params['session_id'],
          }
        # Redirect to account with error indicator
        res.redirect '/account?billing_error=validation'
      rescue Stripe::StripeError => ex
        billing_logger.error 'Stripe session retrieval failed',
          {
            exception: ex,
            session_id: req.params['session_id'],
          }
        # Redirect to account with error indicator
        res.redirect '/account?billing_error=stripe'
      end

      # Redirect to Stripe Customer Portal
      #
      # Allows authenticated users to manage their subscription, billing info, and payment methods.
      #
      # GET /billing/portal
      #
      def customer_portal_redirect
        res.do_not_cache!

        # Load default organization for customer
        org = find_or_create_default_organization(cust)

        unless org.stripe_customer_id
          billing_logger.warn 'No Stripe customer ID for organization',
            {
              org_extid: org.extid,
              customer_extid: cust.extid,
            }
          res.redirect '/account'
          return
        end

        site_host  = Onetime.conf['site']['host']
        is_secure  = Onetime.conf['site']['ssl']
        protocol   = is_secure ? 'https' : 'http'

        # Return to billing overview for the specific organization
        return_url = "#{protocol}://#{site_host}/billing/#{org.extid}/overview"

        # Create Stripe Customer Portal session
        portal_session = Stripe::BillingPortal::Session.create(
          {
            customer: org.stripe_customer_id,
            return_url: return_url,
          },
        )

        billing_logger.info 'Customer portal session created',
          {
            extid: org.extid,
            customer_id: org.stripe_customer_id,
          }

        res.redirect portal_session.url
      rescue Stripe::StripeError => ex
        billing_logger.error 'Stripe portal session creation failed',
          {
            exception: ex,
            customer_id: org&.stripe_customer_id,
          }
        res.redirect '/account'
      end

      private

      # Detect region from request
      #
      # Future: Use GeoIP or CloudFlare headers for accurate region detection
      #
      # @return [String] Region code (default: 'EU')
      def detect_region
        # For Phase 1, default to EU
        # Future: Use req.env['HTTP_CF_IPCOUNTRY'] or GeoIP database
        'EU'
      end

      # Find or create default organization for customer
      #
      # @param customer [Onetime::Customer] Customer instance
      # @return [Onetime::Organization] Default organization
      def find_or_create_default_organization(customer)
        # Find existing default organization
        orgs        = customer.organization_instances.to_a
        default_org = orgs.find { |org| org.is_default }

        return default_org if default_org

        # Create default organization (self-healing fallback)
        # See: apps/web/auth/operations/create_default_workspace.rb
        org = Onetime::Organization.create!(
          "#{customer.email}'s Workspace",
          customer,
          customer.email,
          is_default: true,
        )

        billing_logger.info 'Created default organization',
          {
            org_extid: org.extid,
            customer_extid: customer.extid,
          }

        org
      end
    end
  end
end
