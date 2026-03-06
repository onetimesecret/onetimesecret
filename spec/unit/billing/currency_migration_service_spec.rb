# spec/unit/billing/currency_migration_service_spec.rb
#
# frozen_string_literal: true

# Unit tests for Billing::CurrencyMigrationService module.
#
# Tests currency conflict detection, diagnostic assessment, and
# migration execution (graceful and immediate paths).
#
# Run: pnpm run test:rspec spec/unit/billing/currency_migration_service_spec.rb

require 'spec_helper'

require_relative '../../../apps/web/billing/lib/currency_migration_service'
require_relative '../../../apps/web/billing/lib/stripe_client'

RSpec.describe Billing::CurrencyMigrationService, billing: true do
  # =========================================================================
  # Detection
  # =========================================================================

  describe '.currency_conflict?' do
    it 'returns true for Stripe currency conflict error' do
      error = Stripe::InvalidRequestError.new(
        'You cannot combine currencies on a single customer. This customer has had a subscription or payment in eur, but you are trying to pay in cad.',
        'currency'
      )
      expect(described_class.currency_conflict?(error)).to be true
    end

    it 'returns true for payment variant wording' do
      error = Stripe::InvalidRequestError.new(
        'You cannot combine currencies on a single customer. This customer has had a payment in gbp, but you are trying to charge in cad.',
        'currency'
      )
      expect(described_class.currency_conflict?(error)).to be true
    end

    it 'returns true for new format (active objects, currency at end)' do
      error = Stripe::InvalidRequestError.new(
        'You cannot combine currencies on a single customer. This customer has an active subscription, subscription schedule, discount, quote, invoice item or active subscription mode checkout session with currency cad.',
        'currency'
      )
      expect(described_class.currency_conflict?(error)).to be true
    end

    it 'returns false for non-currency Stripe errors' do
      error = Stripe::InvalidRequestError.new(
        'No such price: price_abc123',
        'price'
      )
      expect(described_class.currency_conflict?(error)).to be false
    end

    it 'returns false for non-InvalidRequestError' do
      error = Stripe::APIError.new('Internal error')
      expect(described_class.currency_conflict?(error)).to be false
    end
  end

  describe '.parse_currency_conflict' do
    it 'extracts currency pair from error message' do
      error = Stripe::InvalidRequestError.new(
        'You cannot combine currencies on a single customer. This customer has had a subscription or payment in eur, but you are trying to pay in cad.',
        'currency'
      )

      result = described_class.parse_currency_conflict(error)

      expect(result).to eq(
        existing_currency: 'eur',
        requested_currency: 'cad'
      )
    end

    it 'handles uppercase currencies in message' do
      error = Stripe::InvalidRequestError.new(
        'This customer has had a subscription or payment in EUR, but you are trying to pay in CAD.',
        'currency'
      )

      result = described_class.parse_currency_conflict(error)

      expect(result[:existing_currency]).to eq('eur')
      expect(result[:requested_currency]).to eq('cad')
    end

    it 'extracts existing currency from new format and returns nil requested without hint' do
      error = Stripe::InvalidRequestError.new(
        'You cannot combine currencies on a single customer. This customer has an active subscription, subscription schedule, discount, quote, invoice item or active subscription mode checkout session with currency eur.',
        'currency'
      )

      result = described_class.parse_currency_conflict(error)

      expect(result[:existing_currency]).to eq('eur')
      expect(result[:requested_currency]).to be_nil
    end

    it 'uses requested_currency_hint for new format that omits requested currency' do
      error = Stripe::InvalidRequestError.new(
        'You cannot combine currencies on a single customer. This customer has an active subscription, subscription schedule, discount, quote, invoice item or active subscription mode checkout session with currency eur.',
        'currency'
      )

      result = described_class.parse_currency_conflict(error, requested_currency_hint: 'CAD')

      expect(result[:existing_currency]).to eq('eur')
      expect(result[:requested_currency]).to eq('cad')
    end

    it 'returns nil for non-matching error' do
      error = Stripe::InvalidRequestError.new('No such price', 'price')
      expect(described_class.parse_currency_conflict(error)).to be_nil
    end
  end

  # =========================================================================
  # Diagnostics
  # =========================================================================

  describe '.assess_migration' do
    let(:customer_id) { 'cus_test_123' }
    let(:org) do
      double('Organization',
        stripe_customer_id: customer_id,
        stripe_subscription_id: 'sub_123',
      )
    end
    let(:mock_customer) do
      Stripe::Customer.construct_from({
        id: customer_id,
        balance: 0,
      })
    end
    let(:target_price_id) { 'price_cad_456' }
    let(:target_plan) { double(name: 'Plus Monthly (USD)', amount: '2900', interval: 'month') }

    let(:current_plan) { double(name: 'Plus Monthly (EUR)') }

    before do
      allow(Stripe::Customer).to receive(:retrieve).with(customer_id).and_return(mock_customer)
      allow(::Billing::Plan).to receive(:find_by_stripe_price_id).with(target_price_id).and_return(target_plan)
      allow(::Billing::Plan).to receive(:find_by_stripe_price_id).with('price_eur').and_return(current_plan)
    end

    context 'with active subscription and clean state' do
      let(:subscription) do
        Stripe::Subscription.construct_from({
          id: 'sub_123', object: 'subscription', customer: customer_id,
          status: 'active', currency: 'eur',
          cancel_at_period_end: false, discounts: [],
          items: { data: [{ price: { id: 'price_eur', unit_amount: 2900, recurring: { interval: 'month' } }, current_period_end: (Time.now + 30 * 86400).to_i }] },
          metadata: {},
        })
      end

      before do
        allow(Stripe::Subscription).to receive(:retrieve).with('sub_123').and_return(subscription)
        allow(Stripe::Checkout::Session).to receive(:list).and_return(double(data: []))
        allow(Stripe::InvoiceItem).to receive(:list).and_return(double(data: []))
      end

      it 'returns can_migrate true with no blockers' do
        result = described_class.assess_migration(org, 'eur', 'cad', target_price_id)

        expect(result[:can_migrate]).to be true
        expect(result[:blockers]).to be_empty
        expect(result[:current_plan]).not_to be_nil
        expect(result[:existing_currency]).to eq('eur')
        expect(result[:requested_currency]).to eq('cad')
      end

      it 'builds current_plan from subscription' do
        result = described_class.assess_migration(org, 'eur', 'cad', target_price_id)

        expect(result[:current_plan][:current_period_end]).to be_a(Integer)
        expect(result[:current_plan][:cancel_at_period_end]).to be false
      end

      it 'builds requested_plan from catalog' do
        result = described_class.assess_migration(org, 'eur', 'cad', target_price_id)

        expect(result[:requested_plan][:name]).to eq('Plus Monthly (USD)')
        expect(result[:requested_plan][:price_id]).to eq(target_price_id)
      end
    end

    context 'with past_due subscription' do
      let(:subscription) do
        Stripe::Subscription.construct_from({
          id: 'sub_123', object: 'subscription', customer: customer_id,
          status: 'past_due', currency: 'eur',
          cancel_at_period_end: false, discounts: [],
          items: { data: [{ price: { id: 'price_eur', unit_amount: 2900, recurring: { interval: 'month' } }, current_period_end: (Time.now + 30 * 86400).to_i }] },
          metadata: {},
        })
      end

      before do
        allow(Stripe::Subscription).to receive(:retrieve).with('sub_123').and_return(subscription)
        allow(Stripe::Checkout::Session).to receive(:list).and_return(double(data: []))
        allow(Stripe::InvoiceItem).to receive(:list).and_return(double(data: []))
      end

      it 'blocks migration' do
        result = described_class.assess_migration(org, 'eur', 'cad', target_price_id)

        expect(result[:can_migrate]).to be false
        expect(result[:blockers]).to include(/past_due/)
      end
    end

    context 'with non-zero credit balance' do
      let(:subscription) do
        Stripe::Subscription.construct_from({
          id: 'sub_123', object: 'subscription', customer: customer_id,
          status: 'active', currency: 'eur',
          cancel_at_period_end: false, discounts: [],
          items: { data: [{ price: { id: 'price_eur', unit_amount: 2900, recurring: { interval: 'month' } }, current_period_end: (Time.now + 30 * 86400).to_i }] },
          metadata: {},
        })
      end

      before do
        allow(mock_customer).to receive(:balance).and_return(-5000)
        allow(Stripe::Subscription).to receive(:retrieve).with('sub_123').and_return(subscription)
        allow(Stripe::Checkout::Session).to receive(:list).and_return(double(data: []))
        allow(Stripe::InvoiceItem).to receive(:list).and_return(double(data: []))
      end

      it 'warns about credit balance' do
        result = described_class.assess_migration(org, 'eur', 'cad', target_price_id)

        expect(result[:warnings][:has_credit_balance]).to be true
        expect(result[:warnings][:credit_balance_amount]).to eq(-5000)
      end
    end

    context 'with pending invoice items in old currency' do
      let(:subscription) do
        Stripe::Subscription.construct_from({
          id: 'sub_123', object: 'subscription', customer: customer_id,
          status: 'active', currency: 'eur',
          cancel_at_period_end: false, discounts: [],
          items: { data: [{ price: { id: 'price_eur', unit_amount: 2900, recurring: { interval: 'month' } }, current_period_end: (Time.now + 30 * 86400).to_i }] },
          metadata: {},
        })
      end

      before do
        allow(Stripe::Subscription).to receive(:retrieve).with('sub_123').and_return(subscription)
        allow(Stripe::Checkout::Session).to receive(:list).and_return(double(data: []))

        items = [
          double(id: 'ii_1', currency: 'eur', amount: 500),
          double(id: 'ii_2', currency: 'eur', amount: 300),
        ]
        allow(Stripe::InvoiceItem).to receive(:list).and_return(double(data: items))
      end

      it 'warns about pending items' do
        result = described_class.assess_migration(org, 'eur', 'cad', target_price_id)

        expect(result[:warnings][:has_pending_invoice_items]).to be true
      end
    end

    context 'with amount-off coupon in old currency' do
      let(:subscription) do
        Stripe::Subscription.construct_from({
          id: 'sub_123', object: 'subscription', customer: customer_id,
          status: 'active', currency: 'eur',
          cancel_at_period_end: false,
          discounts: [{ coupon: { id: 'coupon_10_eur', amount_off: 1000, currency: 'eur', name: '10 EUR off' } }],
          items: { data: [{ price: { id: 'price_eur', unit_amount: 2900, recurring: { interval: 'month' } }, current_period_end: (Time.now + 30 * 86400).to_i }] },
          metadata: {},
        })
      end

      before do
        allow(Stripe::Subscription).to receive(:retrieve).with('sub_123').and_return(subscription)
        allow(Stripe::Checkout::Session).to receive(:list).and_return(double(data: []))
        allow(Stripe::InvoiceItem).to receive(:list).and_return(double(data: []))
      end

      it 'warns about incompatible coupon' do
        result = described_class.assess_migration(org, 'eur', 'cad', target_price_id)

        expect(result[:warnings][:has_incompatible_coupons]).to be true
      end
    end

    # Regression: Stripe API returns `discounts` (array) not `discount` (singular).
    # Prior to fix, accessing sub.discount on newer API versions raised NoMethodError.
    context 'with discounts array containing amount-off coupon (Stripe API regression)' do
      let(:subscription) do
        Stripe::Subscription.construct_from({
          id: 'sub_123', object: 'subscription', customer: customer_id,
          status: 'active', currency: 'eur',
          cancel_at_period_end: false,
          discounts: [{ coupon: { id: 'coupon_10_eur', amount_off: 1000, currency: 'eur', name: '10 EUR off' } }],
          items: { data: [{ price: { id: 'price_eur', unit_amount: 2900, recurring: { interval: 'month' } }, current_period_end: (Time.now + 30 * 86400).to_i }] },
          metadata: {},
        })
      end

      before do
        allow(Stripe::Subscription).to receive(:retrieve).with('sub_123').and_return(subscription)
        allow(Stripe::Checkout::Session).to receive(:list).and_return(double(data: []))
        allow(Stripe::InvoiceItem).to receive(:list).and_return(double(data: []))
      end

      it 'detects incompatible coupon from discounts array' do
        result = described_class.assess_migration(org, 'eur', 'cad', target_price_id)

        expect(result[:warnings][:has_incompatible_coupons]).to be true
      end
    end

    context 'with empty discounts array (Stripe API regression)' do
      let(:subscription) do
        Stripe::Subscription.construct_from({
          id: 'sub_123', object: 'subscription', customer: customer_id,
          status: 'active', currency: 'eur',
          cancel_at_period_end: false,
          discounts: [],
          items: { data: [{ price: { id: 'price_eur', unit_amount: 2900, recurring: { interval: 'month' } }, current_period_end: (Time.now + 30 * 86400).to_i }] },
          metadata: {},
        })
      end

      before do
        allow(Stripe::Subscription).to receive(:retrieve).with('sub_123').and_return(subscription)
        allow(Stripe::Checkout::Session).to receive(:list).and_return(double(data: []))
        allow(Stripe::InvoiceItem).to receive(:list).and_return(double(data: []))
      end

      it 'does not warn about incompatible coupons' do
        result = described_class.assess_migration(org, 'eur', 'cad', target_price_id)

        expect(result[:warnings][:has_incompatible_coupons]).to be false
      end
    end

    context 'with percentage coupon in discounts array (Stripe API regression)' do
      let(:subscription) do
        Stripe::Subscription.construct_from({
          id: 'sub_123', object: 'subscription', customer: customer_id,
          status: 'active', currency: 'eur',
          cancel_at_period_end: false,
          discounts: [{ coupon: { id: 'coupon_20pct', percent_off: 20, amount_off: nil, currency: nil, name: '20% off' } }],
          items: { data: [{ price: { id: 'price_eur', unit_amount: 2900, recurring: { interval: 'month' } }, current_period_end: (Time.now + 30 * 86400).to_i }] },
          metadata: {},
        })
      end

      before do
        allow(Stripe::Subscription).to receive(:retrieve).with('sub_123').and_return(subscription)
        allow(Stripe::Checkout::Session).to receive(:list).and_return(double(data: []))
        allow(Stripe::InvoiceItem).to receive(:list).and_return(double(data: []))
      end

      it 'does not warn about percentage coupons' do
        result = described_class.assess_migration(org, 'eur', 'cad', target_price_id)

        expect(result[:warnings][:has_incompatible_coupons]).to be false
      end
    end
  end

  # =========================================================================
  # Migration Execution
  # =========================================================================

  describe '.execute_graceful_migration' do
    let(:org) do
      double('Organization',
        objid: 'org_obj_123',
        extid: 'org_ext_123',
        stripe_customer_id: 'cus_123',
        stripe_subscription_id: 'sub_123',
        owners: [double(extid: 'cust_ext_456')],
      )
    end

    let(:period_end) { (Time.now + 30 * 86400).to_i }

    let(:subscription) do
      Stripe::Subscription.construct_from({
        id: 'sub_123', object: 'subscription',
        customer: 'cus_123', status: 'active', currency: 'eur',
        cancel_at_period_end: false,
        items: { data: [{ id: 'si_123', price: { id: 'price_eur_123', unit_amount: 2900, recurring: { interval: 'month' } }, current_period_end: period_end }] },
        metadata: {},
      })
    end

    before do
      allow(Stripe::Subscription).to receive(:retrieve).with('sub_123').and_return(subscription)
      allow(Stripe::Subscription).to receive(:update).and_return(subscription)
      allow(Stripe::Checkout::Session).to receive(:list).and_return(double(data: []))
      allow(org).to receive(:set_currency_migration_intent!)
    end

    it 'cancels at period end and stores migration intent' do
      result = described_class.execute_graceful_migration(org, 'price_cad_456')

      expect(Stripe::Subscription).to have_received(:update).with(
        'sub_123',
        hash_including(cancel_at_period_end: true)
      )
      expect(org).to have_received(:set_currency_migration_intent!).with('price_cad_456', period_end)
      expect(result[:success]).to be true
      expect(result[:migration][:mode]).to eq('graceful')
      expect(result[:migration][:cancel_at]).to eq(period_end)
    end

    it 'expires orphaned checkout sessions before migration' do
      orphaned = double(id: 'cs_orphaned')
      allow(Stripe::Checkout::Session).to receive(:list).and_return(double(data: [orphaned]))
      allow(Stripe::Checkout::Session).to receive(:expire)

      described_class.execute_graceful_migration(org, 'price_cad_456')

      expect(Stripe::Checkout::Session).to have_received(:expire).with('cs_orphaned')
    end
  end

  describe '.execute_immediate_migration' do
    let(:org) do
      double('Organization',
        objid: 'org_obj_123',
        extid: 'org_ext_123',
        stripe_customer_id: 'cus_123',
        stripe_subscription_id: 'sub_123',
        owners: [double(extid: 'cust_ext_456')],
      )
    end

    let(:period_start) { (Time.now - 15 * 86400).to_i }
    let(:period_end) { (Time.now + 15 * 86400).to_i }

    let(:subscription) do
      Stripe::Subscription.construct_from({
        id: 'sub_123', object: 'subscription',
        customer: 'cus_123', status: 'active', currency: 'eur',
        items: { data: [{ id: 'si_123', price: { id: 'price_eur', unit_amount: 2900 }, current_period_start: period_start, current_period_end: period_end }] },
        metadata: {},
      })
    end

    let(:checkout_session) do
      double(id: 'cs_new_123', url: 'https://checkout.stripe.com/c/pay/cs_new_123')
    end

    let(:proration_preview) do
      Stripe::Invoice.construct_from({
        id: 'in_preview',
        lines: { data: [
          { amount: -1450, description: 'Unused time on Plus Monthly' },
          { amount: 0, description: 'Remaining time on Plus Monthly' },
        ] },
      })
    end

    before do
      allow(Stripe::Subscription).to receive(:retrieve).with('sub_123').and_return(subscription)
      allow(Stripe::Subscription).to receive(:cancel).and_return(subscription)
      allow(Stripe::Checkout::Session).to receive(:list).and_return(double(data: []))
      allow(Stripe::InvoiceItem).to receive(:list).and_return(double(data: []))
      allow(Stripe::Invoice).to receive(:list).and_return(double(data: []))
      allow(Stripe::Invoice).to receive(:create_preview).and_return(proration_preview)
      allow(Billing::StripeClient).to receive(:new).and_return(
        double(create: checkout_session)
      )
      allow(org).to receive(:clear_currency_migration_intent!)
    end

    it 'cancels subscription and creates new checkout' do
      result = described_class.execute_immediate_migration(
        org, 'price_cad_456',
        success_url: 'https://example.com/success',
        cancel_url: 'https://example.com/cancel',
      )

      expect(Stripe::Subscription).to have_received(:cancel).with(
        'sub_123',
        hash_including(metadata: hash_including(currency_migration: 'immediate'))
      )
      expect(result[:success]).to be true
      expect(result[:migration][:mode]).to eq('immediate')
      expect(result[:migration][:checkout_url]).to include('stripe.com')
      expect(result[:migration][:refund_amount]).to be_a(Integer)
      expect(result[:migration][:refund_formatted]).to be_a(String)
    end

    it 'clears migration intent after completion' do
      described_class.execute_immediate_migration(
        org, 'price_cad_456',
        success_url: 'https://example.com/success',
        cancel_url: 'https://example.com/cancel',
      )

      expect(org).to have_received(:clear_currency_migration_intent!)
    end

    it 'works when org has no active subscription' do
      allow(org).to receive(:stripe_subscription_id).and_return(nil)

      result = described_class.execute_immediate_migration(
        org, 'price_cad_456',
        success_url: 'https://example.com/success',
        cancel_url: 'https://example.com/cancel',
      )

      expect(Stripe::Subscription).not_to have_received(:cancel)
      expect(result[:success]).to be true
    end

    it 'issues prorated refund using Stripe invoice preview amount' do
      invoice = double(id: 'in_123', payment_intent: 'pi_123')
      allow(Stripe::Invoice).to receive(:list).and_return(double(data: [invoice]))
      allow(Stripe::Invoice).to receive(:void_invoice).and_return(nil)
      allow(Stripe::Refund).to receive(:create).and_return(double(id: 're_123'))

      result = described_class.execute_immediate_migration(
        org, 'price_cad_456',
        success_url: 'https://example.com/success',
        cancel_url: 'https://example.com/cancel',
      )

      expect(Stripe::Invoice).to have_received(:create_preview).with(
        hash_including(
          customer: 'cus_123',
          subscription: 'sub_123',
          subscription_proration_behavior: 'create_prorations'
        )
      )
      expect(Stripe::Refund).to have_received(:create).with(
        hash_including(
          payment_intent: 'pi_123',
          amount: 1450,
          reason: 'requested_by_customer'
        )
      )
      expect(result[:migration][:refund_amount]).to eq(1450)
    end

    it 'falls back to manual calculation when invoice preview fails' do
      allow(Stripe::Invoice).to receive(:create_preview)
        .and_raise(Stripe::InvalidRequestError.new('No such subscription', 'subscription'))
      allow(Stripe::Invoice).to receive(:void_invoice).and_return(nil)
      allow(OT).to receive(:ld)

      result = described_class.execute_immediate_migration(
        org, 'price_cad_456',
        success_url: 'https://example.com/success',
        cancel_url: 'https://example.com/cancel',
      )

      # Manual calculation should produce a positive credit (halfway through period)
      expect(result[:migration][:refund_amount]).to be > 0
      expect(result[:migration][:refund_amount]).to be_a(Integer)
    end
  end
end
