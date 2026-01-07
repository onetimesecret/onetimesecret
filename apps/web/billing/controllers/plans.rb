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
      # GET /billing/plans/:tier/:billing_cycle
      #
      # @param [String] tier The selected plan tier (e.g., 'single_team', 'multi_team')
      # @param [String] billing_cycle The chosen billing frequency ('monthly', 'yearly')
      #
      # @return [HTTP 302] Redirects to Stripe Checkout Session
      #
      def checkout_redirect
        tier          = req.params['tier'] ||= 'single_team'
        billing_cycle = req.params['billing_cycle'] ||= 'monthly'

        # Detect region from request (future: use GeoIP)
        region = detect_region

        billing_logger.debug 'Plan checkout request', {
          tier: tier,
          billing_cycle: billing_cycle,
          region: region,
        }

        # Get plan from cache
        plan = ::Billing::Plan.get_plan(tier, billing_cycle, region)

        unless plan
          billing_logger.warn 'Plan not found in cache', {
            tier: tier,
            billing_cycle: billing_cycle,
            region: region,
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
        }

        # Pre-fill customer email if authenticated
        unless cust.anonymous?
          session_params[:customer_email]      = cust.email
          session_params[:client_reference_id] = cust.extid
        end

        # Add metadata for debugging (NOT source of truth - catalog is authoritative)
        #
        # NOTE: plan_id is stored as debug_info only. The authoritative plan_id
        # is resolved from price_id via catalog lookup in webhook processing.
        # This metadata is useful for debugging subscription creation but should
        # NOT be relied upon for billing decisions.
        #
        # @see Billing::PlanValidator.resolve_plan_id
        # @see WithOrganizationBilling#extract_plan_id_from_subscription
        #
        session_params[:subscription_data] = {
          metadata: {
            debug_info: {
              checkout_plan_id: plan.plan_id,
              checkout_tier: tier,
              checkout_region: region,
              checkout_timestamp: Time.now.iso8601,
            }.to_json,
            customer_extid: cust.extid,
          },
        }

        # Create Stripe Checkout Session
        checkout_session = Stripe::Checkout::Session.create(session_params)

        billing_logger.info 'Checkout session created', {
          session_id: checkout_session.id,
          tier: tier,
          billing_cycle: billing_cycle,
          region: region,
        }

        res.redirect checkout_session.url
      rescue Stripe::StripeError => ex
        billing_logger.error 'Stripe checkout session creation failed', {
          exception: ex,
          tier: tier,
          billing_cycle: billing_cycle,
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
        logic = Billing::Logic::Welcome::ProcessCheckoutSession.new(strategy_result, req.params, locale)
        logic.raise_concerns
        logic.process

        res.redirect '/account'
      rescue Onetime::FormError => ex
        billing_logger.warn 'Welcome page validation failed', {
          error: ex.message,
          session_id: req.params['session_id'],
        }
        res.redirect '/account'
      rescue Stripe::StripeError => ex
        billing_logger.error 'Stripe session retrieval failed', {
          exception: ex,
          session_id: req.params['session_id'],
        }
        res.redirect '/account'
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
          billing_logger.warn 'No Stripe customer ID for organization', {
            org_extid: org.extid,
            customer_extid: cust.extid,
          }
          res.redirect '/account'
          return
        end

        site_host  = Onetime.conf['site']['host']
        is_secure  = Onetime.conf['site']['ssl']
        return_url = "#{is_secure ? 'https' : 'http'}://#{site_host}/account"

        # Create Stripe Customer Portal session
        portal_session = Stripe::BillingPortal::Session.create({
          customer: org.stripe_customer_id,
          return_url: return_url,
        },
                                                              )

        billing_logger.info 'Customer portal session created', {
          extid: org.objid,
          customer_id: org.stripe_customer_id,
        }

        res.redirect portal_session.url
      rescue Stripe::StripeError => ex
        billing_logger.error 'Stripe portal session creation failed', {
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

        # Create default organization
        org            = Onetime::Organization.create!(
          "#{customer.email}'s Workspace",
          customer,
          customer.email,
        )
        org.is_default = true
        org.save

        billing_logger.info 'Created default organization', {
          org_extid: org.extid,
          customer_extid: customer.extid,
        }

        org
      end
    end
  end
end
