# apps/web/billing/operations/create_checkout_link.rb
#
# frozen_string_literal: true

require 'securerandom'

require 'onetime/models/colonel_audit_event'

require_relative '../lib/plan_resolver'
require_relative '../lib/pmc_resource_missing'
require_relative '../lib/stripe_client'
require_relative '../lib/subscription_guard'
require_relative 'grant_probono_entitlements'

module Billing
  module Operations
    # Result of CreateCheckoutLink.call
    #
    # @!attribute status [Symbol] One of :created, :would_create, :failed
    # @!attribute url [String, nil] Stripe-hosted checkout URL (nil unless :created)
    # @!attribute session_id [String, nil] Checkout Session id (nil unless :created)
    # @!attribute price_id [String, nil] Resolved Stripe price id
    # @!attribute plan_id [String, nil] Canonical family plan id
    # @!attribute expires_at [Integer, nil] Unix timestamp when the session
    #   expires (Checkout Sessions expire 24h after creation, fixed by Stripe)
    # @!attribute reason [String, nil] Failure reason when :failed
    CheckoutLinkResult = Data.define(:status, :url, :session_id, :price_id, :plan_id, :expires_at, :reason) do
      def created?      = status == :created
      def would_create? = status == :would_create
      def skipped?      = would_create?
      def failed?       = status == :failed
    end

    # CreateCheckoutLink — Create a Stripe Checkout Session for a specific
    # customer on behalf of support/admin (a "checkout link" the admin can
    # hand to the customer).
    #
    # The ONE implementation of the verb; the colonel
    # `ColonelAPI::Logic::Colonel::CreateCheckoutLink` endpoint and the
    # `bin/ots billing checkout-links create` CLI command are thin adapters
    # over it. This is a MUTATING admin op (it creates a Stripe object tied
    # to the customer), so it records exactly one ColonelAuditEvent per created
    # session.
    #
    # Setting `:customer` (when the org already has a Stripe customer) or
    # `:customer_email` makes the email read-only in Stripe Checkout — which
    # is the point of this feature: the link is bound to the customer it was
    # created for.
    #
    # The `subscription_data.metadata` keys (orgid, plan_id, tier, region,
    # customer_extid) are load-bearing: the checkout.session.completed
    # webhook handler reads ONLY subscription.metadata['customer_extid'] and
    # metadata['orgid'] and skips the event without them.
    #
    # Usage:
    #   result = Billing::Operations::CreateCheckoutLink.call(
    #     customer: cust, org: org,
    #     product: 'identity_plus_v1', interval: 'monthly',
    #     actor: colonel.extid,
    #   )
    #   result.created?  # => true
    #   result.url       # => "https://checkout.stripe.com/c/pay/cs_..."
    #
    #   # Dry-run (no Stripe call, returns :would_create with the price id)
    #   Billing::Operations::CreateCheckoutLink.call(..., dry_run: true)
    class CreateCheckoutLink
      AUDIT_VERB = 'billing.create_checkout_link'

      # Checkout Sessions expire 24 hours after creation (fixed by Stripe).
      SESSION_TTL = 24 * 60 * 60

      # @param customer [Onetime::Customer] target customer (non-anonymous)
      # @param org [Onetime::Organization] the customer's org the subscription
      #   will attach to (resolve via {default_org_for} when the caller has
      #   only a customer)
      # @param product [String] canonical family plan id (e.g. 'identity_plus_v1')
      # @param interval [String] 'monthly' | 'yearly' (PlanResolver normalizes)
      # @param actor [String] acting admin's PUBLIC identity (extid/email)
      # @param allow_promotion_codes [Boolean] show the promo-code field
      # @param dry_run [Boolean] resolve only; no Stripe call, no audit event
      # @return [CheckoutLinkResult]
      def self.call(customer:, org:, product:, interval:, actor:,
                    allow_promotion_codes: false, dry_run: false)
        new(
          customer: customer,
          org: org,
          product: product,
          interval: interval,
          actor: actor,
          allow_promotion_codes: allow_promotion_codes,
          dry_run: dry_run,
        ).call
      end

      # Shared Checkout::Session param assembly — the single builder for both
      # checkout-creation paths: the self-serve controller
      # (BillingController#create_checkout_session) and this admin op.
      # Request-specific concerns stay with the caller: the controller passes
      # its own cancel_url and the session locale; this op passes the public
      # pricing page and no locale (colonel/CLI adapters have no request).
      #
      # Automatic tax is deployment policy (STRIPE_AUTOMATIC_TAX /
      # billing.yaml 'automatic_tax'), never a per-call choice. When enabled,
      # params gain automatic_tax, tax_id_collection, and
      # billing_address_collection 'required',
      # and — when an existing Stripe customer is bound — customer_update
      # address 'auto', which Stripe requires so subscription renewals can
      # compute tax from the saved address.
      #
      # @param customer [Onetime::Customer] target customer
      # @param org [Onetime::Organization] org the subscription attaches to
      # @param plan_id [String] canonical family plan id
      # @param tier [String] resolved tier (webhook metadata)
      # @param price_id [String] Stripe price id
      # @param cancel_url [String] absolute URL for checkout cancellation
      # @param allow_promotion_codes [Boolean] show the promo-code field.
      #   Deliberately per-caller policy: the self-serve controller passes
      #   true, this admin op defaults to false (Plans#checkout_redirect
      #   hardcodes true on its own path).
      # @param locale [String, nil] Stripe Checkout locale (request paths only)
      # @return [Hash] Stripe::Checkout::Session create params
      def self.build_session_params(customer:, org:, plan_id:, tier:, price_id:,
                                    cancel_url:, allow_promotion_codes:, locale: nil)
        params          = {
          mode: 'subscription',
          line_items: [{ price: price_id, quantity: 1 }],
          success_url: "#{base_url}/billing/welcome?session_id={CHECKOUT_SESSION_ID}",
          cancel_url: cancel_url,
          customer_email: org.billing_email || customer.email,
          client_reference_id: org.objid,
          allow_promotion_codes: allow_promotion_codes,
          subscription_data: {
            # Load-bearing: checkout_completed reads customer_extid + orgid
            # from subscription.metadata and SKIPS the event without them.
            metadata: {
              orgid: org.objid,
              plan_id: plan_id,
              tier: tier,
              region: detect_region,
              customer_extid: customer.extid,
            },
          },
        }
        params[:locale] = locale if locale

        # Binding the session to the existing Stripe customer (or the email)
        # makes the email read-only in Checkout.
        if org.stripe_customer_id
          params[:customer] = org.stripe_customer_id
          params.delete(:customer_email)
        end

        pmc                                   = Onetime.billing_config.payment_method_configuration
        params[:payment_method_configuration] = pmc if pmc

        apply_tax_policy!(params)
      end

      # Applies the deployment tax policy to already-built session params.
      # Shared by every checkout-creation path (this op and
      # Plans#checkout_redirect) so tax treatment cannot diverge by surface.
      # Call after customer handling — customer_update is only valid when a
      # :customer id is bound.
      #
      # @param params [Hash] Stripe::Checkout::Session create params
      # @return [Hash] the same params, mutated
      def self.apply_tax_policy!(params)
        return params unless Onetime.billing_config.automatic_tax?

        params[:automatic_tax]              = { enabled: true }
        params[:billing_address_collection] = 'required'
        # EU B2B: lets businesses enter a VAT number for reverse charge.
        params[:tax_id_collection]          = { enabled: true }
        # Stripe requires an address source for automatic tax on an
        # existing customer object (renewals compute tax from it).
        params[:customer_update]            = { address: 'auto' } if params[:customer]
        params
      end

      # Base URL (protocol + host) from site configuration. Derived from
      # config rather than the request because the CLI and colonel adapters
      # have no request to derive it from.
      def self.base_url
        site_host = Onetime.conf['site']['host']
        is_secure = Onetime.conf.dig('site', 'ssl') != false
        "#{is_secure ? 'https' : 'http'}://#{site_host}"
      end

      def self.detect_region
        OT.conf&.dig('features', 'regions', 'current_jurisdiction') || 'LL'
      end

      # Resolve the customer's default org with the same priority the
      # billing grant path uses (explicit default_org_id, then is_default,
      # then first non-archived org). Adapters (colonel logic, CLI) use this
      # when the caller supplies only a customer.
      #
      # @param customer [Onetime::Customer]
      # @return [Onetime::Organization, nil]
      def self.default_org_for(customer)
        GrantProbonoEntitlements.default_org_for(customer)
      end

      def initialize(customer:, org:, product:, interval:, actor:,
                     allow_promotion_codes:, dry_run:)
        @customer              = customer
        @org                   = org
        @product               = product
        @interval              = interval
        @actor                 = actor
        @allow_promotion_codes = allow_promotion_codes
        @dry_run               = dry_run
      end

      def call
        guard = configuration_guard
        return guard if guard

        duplicate = duplicate_subscription_guard
        return duplicate if duplicate

        resolution = ::Billing::PlanResolver.resolve(product: @product, interval: @interval)
        return failed(resolution.error) unless resolution.success?

        plan = resolution.plan || ::Billing::Plan.load(resolution.plan_id)
        return failed("Plan not found: #{resolution.plan_id}") unless plan

        region_error = region_mismatch(plan)
        return failed(region_error) if region_error

        interval_key = resolution.billing_cycle.delete_suffix('ly') # 'monthly' -> 'month'
        price_data   = plan.price_for(interval_key)
        price_id     = price_data&.dig('stripe_price_id')
        return failed("No price available for #{resolution.billing_cycle} billing") unless price_id

        return would_create(price_id, plan) if @dry_run

        create_session(plan, resolution, price_id)
      rescue Stripe::StripeError => ex
        # ADR-033: the configured payment_method_configuration is only
        # format-checked at boot; existence in the connected Stripe account
        # is discovered here, at first use — so that discovery must be loud
        # and operator-actionable. Log-only: the returned failure stays as
        # generic as any other Stripe error, and no other error is
        # re-classified.
        if ::Billing::PmcResourceMissing.pmc_resource_missing?(ex)
          OT.le "[CreateCheckoutLink] #{::Billing::PmcResourceMissing.operator_message(ex)}"
        end

        failed("Stripe error: #{ex.message}")
      end

      private

      def configuration_guard
        return failed('Billing is not enabled') unless Onetime.billing_config.enabled?
        return failed('Stripe is not configured') if Onetime.billing_config.stripe_key.to_s.strip.empty?

        nil
      end

      # Duplicate-subscription guard (issue #2605), the same predicate both
      # self-serve checkout paths apply — see Billing::SubscriptionGuard.
      #
      # A support-issued link is NOT an exemption. Completing a second checkout
      # creates a second live Stripe subscription and the
      # checkout.session.completed webhook overwrites
      # org.stripe_subscription_id: the customer is charged twice and the first
      # subscription is orphaned (still billing, no longer referenced), which
      # is exactly the state support would then have to unwind by hand.
      #
      # There is deliberately NO operator override. The cases where a second
      # checkout is legitimate — a subscription already set to
      # cancel_at_period_end, and a pending currency migration — are exempt
      # inside the predicate itself, so an override could only ever produce the
      # double-charge state. Plan changes on a live subscription belong in the
      # plan-change flow / Stripe portal, which modifies the existing
      # subscription instead of creating a second one.
      #
      # Runs before plan resolution and before the dry-run branch so
      # `--dry-run` reports the block instead of a link it would refuse to
      # create.
      def duplicate_subscription_guard
        return nil unless ::Billing::SubscriptionGuard.blocking_active_subscription?(@org)

        failed('Organization already has an active subscription')
      end

      # When the deployment is region-scoped, refuse a plan from another
      # region rather than creating a checkout the webhook side would reject.
      def region_mismatch(plan)
        deployment_region = Onetime.billing_config.region
        return nil if deployment_region.nil?

        plan_region = plan.respond_to?(:region) ? plan.region.to_s.strip.upcase : ''
        return nil if plan_region.empty? || plan_region == deployment_region

        "Plan region #{plan_region} does not match deployment region #{deployment_region}"
      end

      def create_session(plan, resolution, price_id)
        session_params = build_session_params(plan, resolution, price_id)

        # Idempotency key: unique per attempt, NOT deterministic. Session
        # creation is a pre-payment operation — an extra session costs
        # nothing and expires on its own; duplicate completions are handled
        # by the checkout.session.completed handler. A deterministic key
        # returns the cached (possibly completed) session on retry and
        # raises IdempotencyError when parameters change within the window.
        # @see apps/web/billing/docs/adr-checkout-idempotency-keys.md
        checkout_session = ::Billing::StripeClient.new.create(
          Stripe::Checkout::Session,
          session_params,
          idempotency_key: SecureRandom.uuid,
        )

        stripe_expiry = checkout_session.respond_to?(:expires_at) && checkout_session.expires_at
        expires_at    = stripe_expiry ? checkout_session.expires_at.to_i : Time.now.to_i + SESSION_TTL

        # One audit event per created session, emitted from the op layer so
        # every adapter (colonel endpoint, CLI) is audited identically.
        Onetime::ColonelAuditEvent.record(
          actor: @actor,
          verb: AUDIT_VERB,
          target: @customer.extid,
          result: :success,
          detail: {
            plan_id: plan.plan_id,
            session_id: checkout_session.id,
            org_extid: @org.extid,
          },
        )

        CheckoutLinkResult.new(
          status: :created,
          url: checkout_session.url,
          session_id: checkout_session.id,
          price_id: price_id,
          plan_id: plan.plan_id,
          expires_at: expires_at,
          reason: nil,
        )
      end

      def build_session_params(plan, resolution, price_id)
        self.class.build_session_params(
          customer: @customer,
          org: @org,
          plan_id: plan.plan_id,
          tier: resolution.tier,
          price_id: price_id,
          # Support-initiated link: there may be no org page context, so the
          # cancel target is the public pricing page.
          cancel_url: "#{self.class.base_url}/pricing",
          allow_promotion_codes: @allow_promotion_codes,
        )
      end

      def would_create(price_id, plan)
        CheckoutLinkResult.new(
          status: :would_create,
          url: nil,
          session_id: nil,
          price_id: price_id,
          plan_id: plan.plan_id,
          expires_at: nil,
          reason: nil,
        )
      end

      def failed(reason)
        CheckoutLinkResult.new(
          status: :failed,
          url: nil,
          session_id: nil,
          price_id: nil,
          plan_id: nil,
          expires_at: nil,
          reason: reason,
        )
      end
    end
  end
end
