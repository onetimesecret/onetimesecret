# apps/web/billing/controllers/plans.rb
#
# frozen_string_literal: true

require_relative 'base'
require 'securerandom'
require 'stripe'

# apply_tax_policy! — required explicitly rather than relying on
# controllers.rb happening to load controllers/billing.rb (which requires the
# op) after this file.
require_relative '../lib/pmc_resource_missing'
require_relative '../operations/create_checkout_link'

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
      # - Idempotency Key: Unique per attempt (UUID); completed-session dedup
      #   happens in the checkout.session.completed webhook handler
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
          # Preserve plan selection through signup so the auth billing hook
          # can carry it through to checkout after authentication.
          res.redirect "/signup?#{Rack::Utils.build_query(product: product, interval: interval)}"
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
          res.redirect "/signup?#{Rack::Utils.build_query(product: product, interval: interval)}"
          return
        end

        # Unauthenticated users must sign up first; preserve plan selection
        if cust.nil? || cust.anonymous?
          res.redirect "/signup?#{Rack::Utils.build_query(product: product, interval: interval)}"
          return
        end

        # Resolved once and reused: this org is the authorization subject of the
        # pre-flight guards below, and the source of the Stripe customer
        # binding further down.
        default_org = default_organization_for(cust)

        # Both pre-flight guards on the caller's default organization —
        # authorization and the duplicate-subscription check — return the path
        # to redirect to, or nil to proceed. See checkout_guard_redirect.
        if (guard_path = checkout_guard_redirect(default_org))
          res.redirect guard_path
          return
        end

        # Get the price for the requested interval
        interval_sym = interval.to_s.sub(/ly$/, '').to_sym  # 'monthly' -> :month
        price_data   = plan.price_for(interval_sym)

        unless price_data&.dig('stripe_price_id')
          billing_logger.warn 'No price found for interval',
            {
              plan_id: plan.plan_id,
              interval: interval,
              available_intervals: plan.available_intervals,
            }
          res.redirect "/signup?#{Rack::Utils.build_query(product: product, interval: interval)}"
          return
        end

        stripe_price_id = price_data['stripe_price_id']

        # Build checkout session parameters
        site_host = Onetime.conf['site']['host']
        is_secure = Onetime.conf.dig('site', 'ssl') != false
        protocol  = is_secure ? 'https' : 'http'

        success_url = "#{protocol}://#{site_host}/billing/welcome?session_id={CHECKOUT_SESSION_ID}"
        cancel_url  = "#{protocol}://#{site_host}/plans"

        session_params = {
          mode: 'subscription',
          line_items: [{
            price: stripe_price_id,
            quantity: 1,
          }],
          success_url: success_url,
          cancel_url: cancel_url,
          locale: req.env['rack.locale']&.first || 'auto',

          # Show the "Add promotion code" field on the Stripe-hosted checkout.
          # Promotion codes must first be created in the Stripe Dashboard
          # (Products → Coupons → Promotion codes).
          allow_promotion_codes: true,
        }

        # Customer handling for authenticated users
        # Reuse existing Stripe Customer if the user has an org with one (returning subscriber)
        # Otherwise, Stripe creates a new customer from email prefill
        unless cust.nil? || cust.anonymous?
          session_params[:client_reference_id] = cust.extid

          # Reuse the Stripe customer on the caller's default organization
          # (returning subscriber); otherwise Stripe creates one from the email
          # prefill. Safe to bind unconditionally here because control only
          # reaches this point when default_org is nil or the caller owns it —
          # see the authorization gate above.
          if default_org&.stripe_customer_id.to_s.length.positive?
            session_params[:customer] = default_org.stripe_customer_id
          else
            session_params[:customer_email] = cust.email
          end
        end

        # Deployment tax policy (STRIPE_AUTOMATIC_TAX): shared with every
        # other checkout path. Applied after customer handling because
        # customer_update requires a bound :customer id.
        #
        # This path keeps its historical subscription metadata shape — the
        # debug_info JSON blob and customer_extid rather than flat plan/tier/
        # region keys. Those keys are webhook- and Sigma-visible, so changing
        # them requires a consumer audit.
        #
        # Dashboard prerequisites when enabled (Settings → Tax): Stripe Tax
        # active, registrations for applicable jurisdictions, tax codes on
        # products (or a default tax code).
        Billing::Operations::CreateCheckoutLink.apply_tax_policy!(session_params)

        pmc                                           = Onetime.billing_config.payment_method_configuration
        session_params[:payment_method_configuration] = pmc if pmc

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

            # Pin the target approved above with its stable object identifier.
            # When no organization exists yet, omit the key rather than sending
            # an empty identifier.
            orgid: default_org&.objid,
          }.compact,
        }

        # Idempotency key: unique per attempt, NOT deterministic. Duplicate
        # sessions are harmless (they expire unused); duplicate completions are
        # deduped by the checkout.session.completed webhook handler. A
        # time-bucketed key would make Stripe return a cached — possibly
        # already-completed — session on retry within the window.
        # @see apps/web/billing/docs/adr-checkout-idempotency-keys.md
        idempotency_key  = SecureRandom.uuid
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
        # ADR-033: the configured payment_method_configuration is only
        # format-checked at boot; existence in the connected Stripe account
        # is discovered here, at first use — so that discovery must be loud
        # and operator-actionable. Log-only: the user-facing redirect below
        # is unchanged, and no other error is re-classified.
        if ::Billing::PmcResourceMissing.pmc_resource_missing?(ex)
          billing_logger.error ::Billing::PmcResourceMissing.operator_message(ex)
        end

        billing_logger.error 'Stripe checkout session creation failed',
          {
            exception: ex,
            product: product,
            interval: interval,
          }
        res.redirect "/signup?#{Rack::Utils.build_query(product: product, interval: interval)}"
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

        # AUTHORIZATION: the Stripe Customer Portal is the organization's
        # billing root — it exposes the full invoice history and payment
        # instruments, and it can change the payment method and CANCEL the
        # subscription. Membership is not sufficient authority for any of that.
        #
        # cust.default_org_id is not proof of ownership: a default organization
        # can be one the caller merely belongs to. Without this gate, that member
        # is handed the organization's portal.
        #
        # Gate on ownership rather than the manage_billing entitlement.
        # Effective entitlements are the org plan ∩ ROLE_ENTITLEMENTS[role].
        # manage_billing is in OWNER_ENTITLEMENTS only, so the intersection can
        # never grant it to a member or admin — an entitlement gate could not
        # widen access past ownership. It can, however, narrow it below the
        # owner: a deployment whose catalog omits manage_billing from a plan
        # (free_v1 omits it; etc/examples/billing.example.yaml defines the
        # entitlement but lists it in no plan) would have that org's own owner
        # denied their billing portal. Ownership is also the same test every
        # mutating sibling endpoint already applies via
        # load_organization(..., require_owner: true) (controllers/billing.rb).
        #
        # Redirect rather than raise Onetime::Forbidden: this route is declared
        # with no response= (routes.txt), so Otto content-negotiates the error
        # and a browser navigation would render a bare text/plain 403 body.
        unless org.owner?(cust)
          billing_logger.warn 'Customer portal denied: caller does not own organization',
            {
              org_extid: org.extid,
              customer_extid: cust.extid,
            }
          res.redirect '/account?billing_error=not_authorized'
          return
        end

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
        is_secure  = Onetime.conf.dig('site', 'ssl') != false
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

      # Pre-flight guards for checkout_redirect, evaluated against the caller's
      # default organization. Extracted from checkout_redirect to keep that
      # method under the complexity budget; it carries no behaviour of its own
      # beyond these two checks.
      #
      # @param default_org [Onetime::Organization, nil] the caller's default org
      # @return [String, nil] path to redirect to, or nil to proceed to Stripe
      def checkout_guard_redirect(default_org)
        # No organization: nothing to authorize against and no subscription to
        # duplicate. The caller creates and owns an org at completion.
        return nil unless default_org

        # AUTHORIZATION: a checkout started here is applied to default_org — it
        # binds that organization's Stripe Customer (see the customer handling
        # in checkout_redirect) and, on completion, writes the subscription onto
        # that organization. Membership is not sufficient authority to buy on an
        # organization's behalf or to attach a payment instrument to its
        # billing customer.
        #
        # cust.default_org_id is not proof of ownership: a default organization
        # can be one the caller merely belongs to.
        #
        # Deny the checkout outright rather than merely withholding the
        # organization's Stripe customer from the session. Withholding would be
        # strictly worse: it mints a fresh Customer for the member, and
        # ApplySubscriptionToOrg then overwrites the organization's
        # stripe_customer_id with it at completion, detaching the org from its
        # own billing customer. Creating no session at all leaves nothing to
        # resolve and nothing to overwrite. Pinning a target makes resolution
        # deterministic; it does not authorize the purchase. That is this
        # gate's job.
        #
        # Gate on ownership rather than the manage_billing entitlement, as
        # customer_portal_redirect does. Effective entitlements are the org plan
        # ∩ ROLE_ENTITLEMENTS[role] and manage_billing lives in
        # OWNER_ENTITLEMENTS only, so it can never widen access beyond owners —
        # but it can narrow it below them: an org whose plan does not list
        # manage_billing (free_v1, or any deployment whose catalog omits it)
        # would have its own owner denied, and an org with no active
        # subscription is precisely the caller this endpoint exists for.
        # Ownership is also what the sibling self-serve path already requires —
        # BillingController#create_checkout_session loads its org with
        # require_owner: true.
        #
        # Redirect rather than raise Onetime::Forbidden: this route is declared
        # with no response= (routes.txt), so Otto content-negotiates the error
        # and a browser navigation would render a bare text/plain 403 body.
        unless default_org.owner?(cust)
          billing_logger.warn 'Checkout denied: caller does not own organization',
            {
              org_extid: default_org.extid,
              customer_extid: cust.extid,
            }
          return '/account?billing_error=not_authorized'
        end

        # Duplicate-subscription guard (issue #2605). A returning subscriber whose
        # default org already owns a genuinely active, non-canceling subscription
        # must not create a second checkout session (double charge + orphaned
        # subscription). Redirect them to the plan-change UI instead. The
        # currency-migration / resubscribe-after-cancel flows are exempt (the old
        # subscription is winding down) — see org_has_blocking_active_subscription?.
        if org_has_blocking_active_subscription?(default_org)
          billing_logger.info 'Redirect checkout blocked: organization already has an active subscription',
            {
              extid: default_org.extid,
              stripe_subscription_id: default_org.stripe_subscription_id,
            }
          return "/billing/#{default_org.extid}/plans"
        end

        nil
      end

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

      # Find the customer's default organization WITHOUT creating one.
      #
      # Mirrors the customer-reuse lookup in checkout_redirect: prefer the
      # explicit default_org_id, then any (non-archived) org flagged is_default.
      # Returns nil when the customer has no default org, so callers (e.g. the
      # duplicate-subscription guard) can distinguish "no org" from "has org".
      #
      # @param customer [Onetime::Customer, nil] Customer instance
      # @return [Onetime::Organization, nil]
      def default_organization_for(customer)
        return nil if customer.nil? || customer.anonymous?

        orgs        = customer.organization_instances.to_a.reject(&:archived?)
        default_org = if customer.default_org_id.to_s.length.positive?
          orgs.find { |o| o.objid == customer.default_org_id }
        end
        default_org || orgs.find { |o| o.is_default }
      end

      # Find or create default organization for customer
      #
      # @param customer [Onetime::Customer] Customer instance
      # @return [Onetime::Organization] Default organization
      def find_or_create_default_organization(customer)
        orgs = customer.organization_instances.to_a.reject(&:archived?)

        if customer.default_org_id.to_s.length.positive?
          explicit = orgs.find { |o| o.objid == customer.default_org_id }
          return explicit if explicit
        end

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
