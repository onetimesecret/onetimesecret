# apps/web/billing/lib/currency_migration_service.rb
#
# frozen_string_literal: true

require 'stripe'
require_relative 'stripe_client'

module Billing
  # CurrencyMigrationService - Handles Stripe currency conflict resolution
  #
  # When a customer's Stripe account has an existing subscription in one currency
  # and attempts to check out a plan priced in a different currency, Stripe raises:
  #   "You cannot combine currencies on a single customer. This customer has had
  #    a subscription or payment in <old>, but you are trying to pay in <new>."
  #
  # Stripe retains the customer's currency until all subscriptions, invoices, and
  # pending items are cleared. SubscriptionSchedule cannot change currency either.
  #
  # Two migration paths:
  # - Graceful: cancel at period end → store intent → user completes new checkout after
  # - Immediate: cancel now → refund prorated amount → void open invoices → new checkout
  #
  module CurrencyMigrationService
    extend self

    # Regex to extract currencies from Stripe's currency conflict error message.
    # Stripe format: "...had a subscription or payment in <old>...pay in <new>."
    CURRENCY_CONFLICT_PATTERN = /
      has\s+had\s+a.*?(?:subscription|payment)\s+in\s+(\w{3})\b
      .*?
      (?:pay|charge)\s+in\s+(\w{3})\b
    /ix

    # =========================================================================
    # Detection
    # =========================================================================

    # Check if a Stripe error is a currency conflict
    #
    # @param error [Stripe::InvalidRequestError] The Stripe error
    # @return [Boolean] True if the error is a currency conflict
    def currency_conflict?(error)
      return false unless error.is_a?(Stripe::InvalidRequestError)

      error.message.match?(CURRENCY_CONFLICT_PATTERN)
    end

    # Parse currency pair from Stripe error message
    #
    # @param error [Stripe::InvalidRequestError] The Stripe error
    # @return [Hash, nil] { existing_currency: 'eur', requested_currency: 'usd' } or nil
    def parse_currency_conflict(error)
      match = error.message.match(CURRENCY_CONFLICT_PATTERN)
      return nil unless match

      {
        existing_currency: match[1].downcase,
        requested_currency: match[2].downcase,
      }
    end

    # Pre-check for currency mismatch without hitting Stripe errors
    #
    # Compares the subscription's currency with the target plan's currency
    # from the catalog. Returns nil if no mismatch.
    #
    # @param org [Onetime::Organization] Organization with active subscription
    # @param target_price_id [String] Stripe price ID for the target plan
    # @return [Hash, nil] Currency pair if mismatch, nil if currencies match
    def check_currency_mismatch(org, target_price_id)
      return nil unless org.stripe_subscription_id

      # Get current subscription currency
      subscription     = Stripe::Subscription.retrieve(org.stripe_subscription_id)
      current_currency = subscription.currency

      # Get target plan currency from catalog
      target_plan = ::Billing::Plan.find_by_stripe_price_id(target_price_id)
      return nil unless target_plan

      target_currency = target_plan.currency.to_s.downcase
      return nil if target_currency.empty?
      return nil if current_currency == target_currency

      {
        existing_currency: current_currency,
        requested_currency: target_currency,
      }
    end

    # =========================================================================
    # Diagnostics
    # =========================================================================

    # Assess customer state for currency migration
    #
    # Builds the detailed 409 response body with current plan info,
    # requested plan info, and warning flags.
    #
    # @param org [Onetime::Organization] Organization
    # @param existing_currency [String] Current currency (e.g., 'eur')
    # @param requested_currency [String] Target currency (e.g., 'usd')
    # @param requested_price_id [String] Stripe price ID for the target plan
    # @return [Hash] Assessment for frontend display
    def assess_migration(org, existing_currency, requested_currency, requested_price_id)
      result = {
        existing_currency: existing_currency,
        requested_currency: requested_currency,
        can_migrate: true,
        blockers: [],
        warnings: [],
        current_plan: nil,
        requested_plan: nil,
      }

      customer_id = org.stripe_customer_id

      # Build current plan info from active subscription
      if org.stripe_subscription_id
        subscription = Stripe::Subscription.retrieve(org.stripe_subscription_id)
        first_item   = subscription.items.data.first

        if subscription.status == 'past_due'
          result[:blockers] << 'Subscription is past_due — resolve payment before migrating'
          result[:can_migrate] = false
        end

        price                 = first_item&.price
        recurring             = price&.recurring
        result[:current_plan] = {
          name: resolve_plan_name(price&.id),
          price_formatted: format_price(price&.unit_amount, existing_currency, recurring&.interval),
          current_period_end: first_item&.current_period_end,
          cancel_at_period_end: subscription.cancel_at_period_end,
        }
      end

      # Build requested plan info from catalog
      target_plan = ::Billing::Plan.find_by_stripe_price_id(requested_price_id)
      if target_plan
        result[:requested_plan] = {
          name: target_plan.name,
          price_formatted: format_price(target_plan.amount.to_i, requested_currency, target_plan.interval),
          price_id: requested_price_id,
        }
      end

      # Warning flags
      warnings          = check_migration_warnings(customer_id, existing_currency, org.stripe_subscription_id)
      result[:warnings] = warnings

      result
    end

    # =========================================================================
    # Migration Execution
    # =========================================================================

    # Execute graceful migration: cancel at period end + store intent
    #
    # The user keeps their current subscription until period end. After the
    # subscription.deleted webhook fires, the frontend detects the pending
    # migration intent and prompts user to complete checkout in new currency.
    #
    # @param org [Onetime::Organization] Organization
    # @param new_price_id [String] Stripe price ID for the new plan
    # @return [Hash] Migration result
    def execute_graceful_migration(org, new_price_id)
      subscription = Stripe::Subscription.retrieve(org.stripe_subscription_id)
      customer_id  = org.stripe_customer_id

      # Pre-flight
      expire_open_checkout_sessions(customer_id)

      # Cancel at period end (no proration — user keeps full period)
      Stripe::Subscription.update(
        subscription.id,
        {
          cancel_at_period_end: true,
          metadata: {
            currency_migration: 'graceful',
            migration_target_price: new_price_id,
          },
        },
      )

      first_item = subscription.items.data.first
      period_end = first_item.current_period_end

      # Store migration intent on org so frontend knows to prompt for new checkout
      org.set_currency_migration_intent!(new_price_id, period_end)

      {
        success: true,
        migration: {
          mode: 'graceful',
          cancel_at: period_end,
        },
      }
    end

    # Execute immediate migration: cancel + refund + new checkout
    #
    # 1. Expire orphaned checkout sessions
    # 2. Void pending invoice items in old currency
    # 3. Void open invoices
    # 4. Cancel subscription immediately
    # 5. Issue refund for unused time
    # 6. Create new checkout session
    #
    # @param org [Onetime::Organization] Organization
    # @param new_price_id [String] Stripe price ID
    # @param success_url [String] Checkout success redirect URL
    # @param cancel_url [String] Checkout cancel redirect URL
    # @return [Hash] Migration result with checkout URL
    def execute_immediate_migration(org, new_price_id, success_url:, cancel_url:)
      customer_id     = org.stripe_customer_id
      prorated_credit = 0

      # Pre-flight: clean up
      expire_open_checkout_sessions(customer_id)

      if org.stripe_subscription_id
        subscription = Stripe::Subscription.retrieve(org.stripe_subscription_id)
        old_currency = subscription.currency

        # Void pending invoice items in old currency
        void_pending_invoice_items(customer_id, old_currency)

        # Void any open invoices (prevents currency lock)
        void_open_invoices(customer_id)

        # Calculate prorated refund before canceling
        prorated_credit = calculate_prorated_credit(subscription)

        # Cancel immediately
        Stripe::Subscription.cancel(
          subscription.id,
          {
            metadata: {
              currency_migration: 'immediate',
              migration_target_price: new_price_id,
            },
          },
        )

        # Issue refund for prorated unused time if applicable
        if prorated_credit.positive?
          issue_prorated_refund(customer_id, prorated_credit)
        end
      end

      # Create new checkout session
      stripe_client = Billing::StripeClient.new

      session_params = {
        mode: 'subscription',
        customer: customer_id,
        line_items: [{ price: new_price_id, quantity: 1 }],
        success_url: success_url,
        cancel_url: cancel_url,
        subscription_data: {
          metadata: {
            orgid: org.objid,
            currency_migration: 'immediate',
            customer_extid: org.owners.first&.extid,
          },
        },
      }

      checkout_session = stripe_client.create(
        Stripe::Checkout::Session,
        session_params,
      )

      # Clear any pending migration intent (immediate path completes in one step)
      org.clear_currency_migration_intent!

      {
        success: true,
        migration: {
          mode: 'immediate',
          checkout_url: checkout_session.url,
          refund_amount: prorated_credit,
          refund_formatted: format_amount(prorated_credit, subscription&.currency || 'usd'),
        },
      }
    end

    private

    # Check for migration warnings (non-blocking conditions)
    #
    # @param customer_id [String] Stripe customer ID
    # @param existing_currency [String] Current currency
    # @param subscription_id [String, nil] Current subscription ID
    # @return [Hash] Warning flags
    def check_migration_warnings(customer_id, existing_currency, subscription_id)
      warnings = {
        has_credit_balance: false,
        credit_balance_amount: 0,
        has_pending_invoice_items: false,
        has_incompatible_coupons: false,
      }

      # Credit balance check
      customer = Stripe::Customer.retrieve(customer_id)
      balance  = customer.balance || 0
      if balance != 0
        warnings[:has_credit_balance]    = true
        warnings[:credit_balance_amount] = balance
      end

      # Pending invoice items
      begin
        invoice_items                        = Stripe::InvoiceItem.list(
          customer: customer_id,
          pending: true,
          limit: 100,
        )
        old_items                            = invoice_items.data.select { |ii| ii.currency == existing_currency }
        warnings[:has_pending_invoice_items] = old_items.any?
      rescue Stripe::InvalidRequestError
        # May fail if customer has no invoices
      end

      # Amount-off coupon check (currency-specific; percentage coupons are fine)
      if subscription_id
        begin
          sub      = Stripe::Subscription.retrieve(subscription_id)
          discount = sub.discount
          if discount&.coupon&.amount_off && discount.coupon.currency == existing_currency
            warnings[:has_incompatible_coupons] = true
          end
        rescue Stripe::InvalidRequestError
          # Subscription may have been deleted between check and retrieve
        end
      end

      warnings
    end

    # Expire all open checkout sessions for a customer
    #
    # @param customer_id [String] Stripe customer ID
    # @return [Integer] Number of sessions expired
    def expire_open_checkout_sessions(customer_id)
      sessions = Stripe::Checkout::Session.list(
        customer: customer_id,
        status: 'open',
        limit: 20,
      )

      count = 0
      sessions.data.each do |session|
        Stripe::Checkout::Session.expire(session.id)
        count += 1
      rescue Stripe::InvalidRequestError => ex
        OT.lw "[CurrencyMigrationService] Could not expire session #{session.id}: #{ex.message}"
      end

      count
    end

    # Void/delete pending invoice items in the old currency
    #
    # @param customer_id [String] Stripe customer ID
    # @param old_currency [String] Currency to match (e.g., 'eur')
    # @return [Integer] Number of items voided
    def void_pending_invoice_items(customer_id, old_currency)
      invoice_items = Stripe::InvoiceItem.list(
        customer: customer_id,
        pending: true,
        limit: 100,
      )

      count = 0
      invoice_items.data.each do |item|
        next unless item.currency == old_currency

        Stripe::InvoiceItem.delete(item.id)
        count += 1
      rescue Stripe::InvalidRequestError => ex
        OT.lw "[CurrencyMigrationService] Could not delete invoice item #{item.id}: #{ex.message}"
      end

      count
    end

    # Void open invoices to release currency lock
    #
    # @param customer_id [String] Stripe customer ID
    # @return [Integer] Number of invoices voided
    def void_open_invoices(customer_id)
      invoices = Stripe::Invoice.list(
        customer: customer_id,
        status: 'open',
        limit: 20,
      )

      count = 0
      invoices.data.each do |invoice|
        Stripe::Invoice.void_invoice(invoice.id)
        count += 1
      rescue Stripe::InvalidRequestError => ex
        OT.lw "[CurrencyMigrationService] Could not void invoice #{invoice.id}: #{ex.message}"
      end

      count
    end

    # Calculate prorated credit for unused subscription time
    #
    # @param subscription [Stripe::Subscription] Active subscription
    # @return [Integer] Prorated amount in smallest currency unit
    def calculate_prorated_credit(subscription)
      first_item = subscription.items.data.first
      return 0 unless first_item

      period_end   = first_item.current_period_end
      period_start = first_item.current_period_start
      return 0 unless period_end && period_start

      total_period = period_end - period_start
      return 0 if total_period <= 0

      remaining = period_end - Time.now.to_i
      return 0 if remaining <= 0

      amount = first_item.price.unit_amount || 0
      (amount * remaining.to_f / total_period).round
    end

    # Issue refund for prorated unused time
    #
    # Finds the latest paid invoice for the customer and creates a partial refund.
    # Uses Stripe::Refund instead of customer credit balance (credit is currency-specific
    # and won't transfer to the new currency).
    #
    # @param customer_id [String] Stripe customer ID
    # @param amount [Integer] Refund amount in smallest currency unit
    # @param currency [String] Currency code
    # @return [Stripe::Refund, nil] The refund object or nil if no eligible invoice
    def issue_prorated_refund(customer_id, amount)
      # Find the latest paid invoice with a payment intent
      invoices = Stripe::Invoice.list(
        customer: customer_id,
        status: 'paid',
        limit: 1,
      )

      invoice = invoices.data.first
      return nil unless invoice&.payment_intent

      Stripe::Refund.create(
        {
          payment_intent: invoice.payment_intent,
          amount: amount,
          reason: 'requested_by_customer',
          metadata: {
            reason: 'currency_migration_proration',
          },
        },
      )
    rescue Stripe::InvalidRequestError => ex
      OT.lw "[CurrencyMigrationService] Could not issue prorated refund: #{ex.message}"
      nil
    end

    # Resolve plan name from price ID via catalog
    #
    # @param price_id [String] Stripe price ID
    # @return [String] Plan name or 'Unknown'
    def resolve_plan_name(price_id)
      return 'Unknown' unless price_id

      plan = ::Billing::Plan.find_by_stripe_price_id(price_id)
      plan&.name || 'Unknown'
    end

    # Format price for display
    #
    # @param amount_cents [Integer] Amount in smallest currency unit
    # @param currency [String] Currency code
    # @param interval [String] Billing interval ('month' or 'year')
    # @return [String] Formatted price (e.g., "$25.00/mo")
    def format_price(amount_cents, currency, interval)
      return '' unless amount_cents

      symbol = currency_symbol(currency)
      major  = amount_cents / 100.0
      suffix = interval == 'year' ? '/yr' : '/mo'
      "#{symbol}#{format('%.2f', major)}#{suffix}"
    end

    # Format amount for display (cents to human-readable)
    #
    # @param amount_cents [Integer] Amount in smallest currency unit
    # @param currency [String] Currency code
    # @return [String] Formatted amount
    def format_amount(amount_cents, currency)
      symbol = currency_symbol(currency)
      major  = amount_cents / 100.0
      "#{symbol}#{format('%.2f', major)}"
    end

    # Get currency symbol
    #
    # @param currency [String] ISO currency code
    # @return [String] Currency symbol
    def currency_symbol(currency)
      case currency.to_s.downcase
      when 'usd' then '$'
      when 'eur' then "\u20AC"
      when 'gbp' then "\u00A3"
      when 'jpy' then "\u00A5"
      when 'cad' then 'CA$'
      when 'aud' then 'A$'
      when 'chf' then 'CHF '
      else "#{currency.to_s.upcase} "
      end
    end
  end
end
