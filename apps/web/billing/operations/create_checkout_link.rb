# apps/web/billing/operations/create_checkout_link.rb
#
# frozen_string_literal: true

require 'securerandom'

require 'onetime/models/admin_audit_event'

require_relative '../lib/plan_resolver'
require_relative '../lib/stripe_client'
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
    # to the customer), so it records exactly one AdminAuditEvent per created
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
      # @param enable_tax [Boolean] add automatic_tax (and customer_update
      #   address source when reusing an existing Stripe customer)
      # @param allow_promotion_codes [Boolean] show the promo-code field
      # @param dry_run [Boolean] resolve only; no Stripe call, no audit event
      # @return [CheckoutLinkResult]
      def self.call(customer:, org:, product:, interval:, actor:,
                    enable_tax: false, allow_promotion_codes: false, dry_run: false)
        new(
          customer: customer,
          org: org,
          product: product,
          interval: interval,
          actor: actor,
          enable_tax: enable_tax,
          allow_promotion_codes: allow_promotion_codes,
          dry_run: dry_run,
        ).call
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
                     enable_tax:, allow_promotion_codes:, dry_run:)
        @customer              = customer
        @org                   = org
        @product               = product
        @interval              = interval
        @actor                 = actor
        @enable_tax            = enable_tax
        @allow_promotion_codes = allow_promotion_codes
        @dry_run               = dry_run
      end

      def call
        guard = configuration_guard
        return guard if guard

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
        failed("Stripe error: #{ex.message}")
      end

      private

      def configuration_guard
        return failed('Billing is not enabled') unless Onetime.billing_config.enabled?
        return failed('Stripe is not configured') if Onetime.billing_config.stripe_key.to_s.strip.empty?

        nil
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
        Onetime::AdminAuditEvent.record(
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
        params = {
          mode: 'subscription',
          line_items: [{ price: price_id, quantity: 1 }],
          success_url: "#{base_url}/billing/welcome?session_id={CHECKOUT_SESSION_ID}",
          # Support-initiated link: there may be no org page context, so the
          # cancel target is the public pricing page.
          cancel_url: "#{base_url}/pricing",
          customer_email: @org.billing_email || @customer.email,
          client_reference_id: @org.objid,
          allow_promotion_codes: @allow_promotion_codes,
          subscription_data: {
            # Load-bearing: checkout_completed reads customer_extid + orgid
            # from subscription.metadata and SKIPS the event without them.
            metadata: {
              orgid: @org.objid,
              plan_id: plan.plan_id,
              tier: resolution.tier,
              region: detect_region,
              customer_extid: @customer.extid,
            },
          },
        }

        # Binding the session to the existing Stripe customer (or the email)
        # makes the email read-only in Checkout — the point of this feature.
        if @org.stripe_customer_id
          params[:customer] = @org.stripe_customer_id
          params.delete(:customer_email)
        end

        if @enable_tax
          params[:automatic_tax]   = { enabled: true }
          # Stripe requires an address source for automatic tax on an
          # existing customer object.
          params[:customer_update] = { address: 'auto' } if params[:customer]
        end

        params
      end

      # Base URL (protocol + host) from site configuration; this op also
      # serves the CLI, which has no request to derive it from. Mirrors
      # BillingControllers::Base#billing_base_url.
      def base_url
        site_host = Onetime.conf['site']['host']
        is_secure = Onetime.conf.dig('site', 'ssl') != false
        "#{is_secure ? 'https' : 'http'}://#{site_host}"
      end

      def detect_region
        OT.conf&.dig('features', 'regions', 'current_jurisdiction') || 'LL'
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
