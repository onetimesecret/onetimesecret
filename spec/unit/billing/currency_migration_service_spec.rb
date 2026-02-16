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
        'You cannot combine currencies on a single customer. This customer has had a subscription or payment in eur, but you are trying to pay in usd.',
        'currency'
      )
      expect(described_class.currency_conflict?(error)).to be true
    end

    it 'returns true for payment variant wording' do
      error = Stripe::InvalidRequestError.new(
        'You cannot combine currencies on a single customer. This customer has had a payment in gbp, but you are trying to charge in usd.',
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
        'You cannot combine currencies on a single customer. This customer has had a subscription or payment in eur, but you are trying to pay in usd.',
        'currency'
      )

      result = described_class.parse_currency_conflict(error)

      expect(result).to eq(
        existing_currency: 'eur',
        requested_currency: 'usd'
      )
    end

    it 'handles uppercase currencies in message' do
      error = Stripe::InvalidRequestError.new(
        'This customer has had a subscription or payment in EUR, but you are trying to pay in USD.',
        'currency'
      )

      result = described_class.parse_currency_conflict(error)

      expect(result[:existing_currency]).to eq('eur')
      expect(result[:requested_currency]).to eq('usd')
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
    let(:mock_customer) do
      Stripe::Customer.construct_from({
        id: customer_id,
        balance: 0,
      })
    end

    before do
      allow(Stripe::Customer).to receive(:retrieve).with(customer_id).and_return(mock_customer)
    end

    context 'with active subscription and clean state' do
      before do
        sub = Stripe::Subscription.construct_from({
          id: 'sub_123', object: 'subscription', customer: customer_id,
          status: 'active', currency: 'eur',
          cancel_at_period_end: false, discount: nil,
          items: { data: [{ price: { id: 'price_eur', unit_amount: 2900, recurring: { interval: 'month' } }, current_period_end: (Time.now + 30 * 86400).to_i }] },
          metadata: {},
        })
        allow(Stripe::Subscription).to receive(:list).and_return(
          double(data: [sub])
        )
        allow(Stripe::Checkout::Session).to receive(:list).and_return(double(data: []))
        allow(Stripe::InvoiceItem).to receive(:list).and_return(double(data: []))
      end

      it 'returns can_migrate true with no blockers' do
        result = described_class.assess_migration(customer_id, 'eur', 'usd')

        expect(result[:can_migrate]).to be true
        expect(result[:blockers]).to be_empty
        expect(result[:subscription]).not_to be_nil
        expect(result[:subscription][:currency]).to eq('eur')
      end
    end

    context 'with past_due subscription' do
      before do
        sub = Stripe::Subscription.construct_from({
          id: 'sub_past_due', object: 'subscription', customer: customer_id,
          status: 'past_due', currency: 'eur',
          cancel_at_period_end: false, discount: nil,
          items: { data: [{ price: { id: 'price_eur', unit_amount: 2900, recurring: { interval: 'month' } }, current_period_end: (Time.now + 30 * 86400).to_i }] },
          metadata: {},
        })
        allow(Stripe::Subscription).to receive(:list).and_return(
          double(data: [sub])
        )
      end

      it 'blocks migration' do
        result = described_class.assess_migration(customer_id, 'eur', 'usd')

        expect(result[:can_migrate]).to be false
        expect(result[:blockers]).to include(/past_due/)
      end
    end

    context 'with open checkout sessions' do
      before do
        sub = Stripe::Subscription.construct_from({
          id: 'sub_123', object: 'subscription', customer: customer_id,
          status: 'active', currency: 'eur',
          cancel_at_period_end: false, discount: nil,
          items: { data: [{ price: { id: 'price_eur', unit_amount: 2900, recurring: { interval: 'month' } }, current_period_end: (Time.now + 30 * 86400).to_i }] },
          metadata: {},
        })
        allow(Stripe::Subscription).to receive(:list).and_return(double(data: [sub]))
        allow(Stripe::Checkout::Session).to receive(:list).and_return(
          double(data: [double(id: 'cs_orphaned')])
        )
        allow(Stripe::InvoiceItem).to receive(:list).and_return(double(data: []))
      end

      it 'warns about open sessions' do
        result = described_class.assess_migration(customer_id, 'eur', 'usd')

        expect(result[:can_migrate]).to be true
        expect(result[:open_checkout_sessions]).to eq(1)
        expect(result[:warnings]).to include(/open checkout session/)
      end
    end

    context 'with pending invoice items in old currency' do
      before do
        sub = Stripe::Subscription.construct_from({
          id: 'sub_123', object: 'subscription', customer: customer_id,
          status: 'active', currency: 'eur',
          cancel_at_period_end: false, discount: nil,
          items: { data: [{ price: { id: 'price_eur', unit_amount: 2900, recurring: { interval: 'month' } }, current_period_end: (Time.now + 30 * 86400).to_i }] },
          metadata: {},
        })
        allow(Stripe::Subscription).to receive(:list).and_return(double(data: [sub]))
        allow(Stripe::Checkout::Session).to receive(:list).and_return(double(data: []))

        items = [
          double(id: 'ii_1', currency: 'eur', amount: 500),
          double(id: 'ii_2', currency: 'eur', amount: 300),
        ]
        allow(Stripe::InvoiceItem).to receive(:list).and_return(double(data: items))
      end

      it 'warns about pending items' do
        result = described_class.assess_migration(customer_id, 'eur', 'usd')

        expect(result[:pending_invoice_items]).to eq(2)
        expect(result[:warnings]).to include(/pending invoice item/)
      end
    end

    context 'with non-zero credit balance' do
      before do
        allow(mock_customer).to receive(:balance).and_return(-5000)

        sub = Stripe::Subscription.construct_from({
          id: 'sub_123', object: 'subscription', customer: customer_id,
          status: 'active', currency: 'eur',
          cancel_at_period_end: false, discount: nil,
          items: { data: [{ price: { id: 'price_eur', unit_amount: 2900, recurring: { interval: 'month' } }, current_period_end: (Time.now + 30 * 86400).to_i }] },
          metadata: {},
        })
        allow(Stripe::Subscription).to receive(:list).and_return(double(data: [sub]))
        allow(Stripe::Checkout::Session).to receive(:list).and_return(double(data: []))
        allow(Stripe::InvoiceItem).to receive(:list).and_return(double(data: []))
      end

      it 'warns about credit balance' do
        result = described_class.assess_migration(customer_id, 'eur', 'usd')

        expect(result[:credit_balance]).to eq(-5000)
        expect(result[:warnings]).to include(/credit balance/)
      end
    end

    context 'with amount-off coupon in old currency' do
      before do
        coupon = double(amount_off: 1000, currency: 'eur', id: 'coupon_10_eur', name: '10 EUR off')
        discount = double(coupon: coupon)
        sub = Stripe::Subscription.construct_from({
          id: 'sub_123', object: 'subscription', customer: customer_id,
          status: 'active', currency: 'eur',
          cancel_at_period_end: false,
          items: { data: [{ price: { id: 'price_eur', unit_amount: 2900, recurring: { interval: 'month' } }, current_period_end: (Time.now + 30 * 86400).to_i }] },
          metadata: {},
        })
        allow(sub).to receive(:discount).and_return(discount)
        allow(Stripe::Subscription).to receive(:list).and_return(double(data: [sub]))
        allow(Stripe::Checkout::Session).to receive(:list).and_return(double(data: []))
        allow(Stripe::InvoiceItem).to receive(:list).and_return(double(data: []))
      end

      it 'warns about coupon currency mismatch' do
        result = described_class.assess_migration(customer_id, 'eur', 'usd')

        expect(result[:coupons_in_old_currency]).to have_attributes(length: 1)
        expect(result[:coupons_in_old_currency].first[:id]).to eq('coupon_10_eur')
        expect(result[:warnings]).to include(/coupon.*EUR.*cannot transfer/)
      end
    end

    context 'with no active subscription' do
      before do
        allow(Stripe::Subscription).to receive(:list).and_return(double(data: []))
        allow(Stripe::Checkout::Session).to receive(:list).and_return(double(data: []))
        allow(Stripe::InvoiceItem).to receive(:list).and_return(double(data: []))
      end

      it 'warns but allows migration' do
        result = described_class.assess_migration(customer_id, 'eur', 'usd')

        expect(result[:can_migrate]).to be true
        expect(result[:warnings]).to include(/No active subscription/)
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

    let(:subscription) do
      Stripe::Subscription.construct_from({
        id: 'sub_123', object: 'subscription',
        customer: 'cus_123', status: 'active', currency: 'eur',
        cancel_at_period_end: false,
        items: { data: [{ id: 'si_123', price: { id: 'price_eur_123', unit_amount: 2900, recurring: { interval: 'month' } }, current_period_end: (Time.now + 30 * 86400).to_i }] },
        metadata: {},
      })
    end

    let(:schedule) do
      Stripe::SubscriptionSchedule.construct_from({
        id: 'sub_sched_123', object: 'subscription_schedule',
      })
    end

    before do
      allow(Stripe::Subscription).to receive(:retrieve).with('sub_123').and_return(subscription)
      allow(Stripe::Subscription).to receive(:update).and_return(subscription)
      allow(Stripe::SubscriptionSchedule).to receive(:create).and_return(schedule)
      allow(Stripe::Checkout::Session).to receive(:list).and_return(double(data: []))
      allow(Stripe::InvoiceItem).to receive(:list).and_return(double(data: []))
    end

    it 'cancels at period end and creates schedule' do
      result = described_class.execute_graceful_migration(org, 'price_usd_456')

      expect(Stripe::Subscription).to have_received(:update).with(
        'sub_123',
        hash_including(cancel_at_period_end: true)
      )
      expect(Stripe::SubscriptionSchedule).to have_received(:create).with(
        hash_including(
          customer: 'cus_123',
          phases: array_including(
            hash_including(items: [{ price: 'price_usd_456', quantity: 1 }])
          )
        )
      )
      expect(result[:success]).to be true
      expect(result[:migration_type]).to eq('graceful')
      expect(result[:schedule_id]).to eq('sub_sched_123')
    end

    it 'expires orphaned checkout sessions before migration' do
      orphaned = double(id: 'cs_orphaned')
      allow(Stripe::Checkout::Session).to receive(:list).and_return(double(data: [orphaned]))
      allow(Stripe::Checkout::Session).to receive(:expire)

      described_class.execute_graceful_migration(org, 'price_usd_456')

      expect(Stripe::Checkout::Session).to have_received(:expire).with('cs_orphaned')
    end

    it 'voids pending invoice items in old currency' do
      item = double(id: 'ii_old', currency: 'eur')
      allow(Stripe::InvoiceItem).to receive(:list).and_return(double(data: [item]))
      allow(Stripe::InvoiceItem).to receive(:delete)

      described_class.execute_graceful_migration(org, 'price_usd_456')

      expect(Stripe::InvoiceItem).to have_received(:delete).with('ii_old')
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

    let(:subscription) do
      Stripe::Subscription.construct_from({
        id: 'sub_123', object: 'subscription',
        customer: 'cus_123', status: 'active', currency: 'eur',
        items: { data: [{ price: { id: 'price_eur', unit_amount: 2900 } }] },
        metadata: {},
      })
    end

    let(:checkout_session) do
      double(id: 'cs_new_123', url: 'https://checkout.stripe.com/c/pay/cs_new_123')
    end

    before do
      allow(Stripe::Subscription).to receive(:retrieve).with('sub_123').and_return(subscription)
      allow(Stripe::Subscription).to receive(:cancel).and_return(subscription)
      allow(Stripe::Checkout::Session).to receive(:list).and_return(double(data: []))
      allow(Stripe::InvoiceItem).to receive(:list).and_return(double(data: []))
      allow(Billing::StripeClient).to receive(:new).and_return(
        double(create: checkout_session)
      )
    end

    it 'cancels subscription and creates new checkout' do
      result = described_class.execute_immediate_migration(
        org, 'price_usd_456',
        success_url: 'https://example.com/success',
        cancel_url: 'https://example.com/cancel',
      )

      expect(Stripe::Subscription).to have_received(:cancel).with(
        'sub_123',
        hash_including(prorate: true)
      )
      expect(result[:success]).to be true
      expect(result[:migration_type]).to eq('immediate')
      expect(result[:checkout_url]).to include('stripe.com')
    end

    it 'works when org has no active subscription' do
      allow(org).to receive(:stripe_subscription_id).and_return(nil)

      result = described_class.execute_immediate_migration(
        org, 'price_usd_456',
        success_url: 'https://example.com/success',
        cancel_url: 'https://example.com/cancel',
      )

      expect(Stripe::Subscription).not_to have_received(:cancel)
      expect(result[:success]).to be true
    end
  end
end
