# spec/unit/billing/billing_service_spec.rb
#
# frozen_string_literal: true

# Unit tests for Billing::BillingService module.
#
# Tests centralized billing logic including:
# - Plan ID resolution from Stripe subscriptions
# - Sync health computation for organizations
# - Billing state comparison
# - Plan validation
#
# Run: pnpm run test:rspec spec/unit/billing/billing_service_spec.rb

require 'spec_helper'

# Load billing modules
require_relative '../../../apps/web/billing/lib/billing_service'
require_relative '../../../apps/web/billing/metadata'
require_relative '../../../apps/web/billing/models/plan'

RSpec.describe Billing::BillingService, billing: true do
  # Build a minimal Stripe::Subscription for testing
  def build_subscription(subscription_metadata: {}, price_metadata: {}, price_id: 'price_test')
    Stripe::Subscription.construct_from({
      id: 'sub_test_123',
      object: 'subscription',
      customer: 'cus_test',
      status: 'active',
      metadata: subscription_metadata,
      items: {
        data: [{
          price: {
            id: price_id,
            product: 'prod_test',
            metadata: price_metadata,
          },
          current_period_end: (Time.now + 30 * 24 * 60 * 60).to_i,
        }],
      },
    })
  end

  # Mock organization for testing sync status
  let(:mock_org) do
    double('Organization',
      planid: nil,
      stripe_subscription_id: nil,
      subscription_status: nil,
    )
  end

  describe '.resolve_plan_id_from_subscription' do
    context 'when plan is found via catalog lookup' do
      let(:subscription) do
        build_subscription(
          price_id: 'price_catalog_test',
          subscription_metadata: { 'plan_id' => 'stale_plan_id' },
          price_metadata: { 'plan_id' => 'also_stale' },
        )
      end

      let(:mock_plan) { double('Plan', plan_id: 'identity_plus_v1_monthly') }

      before do
        allow(Billing::Plan).to receive(:find_by_stripe_price_id)
          .with('price_catalog_test')
          .and_return(mock_plan)
      end

      it 'prefers catalog lookup over metadata' do
        result = described_class.resolve_plan_id_from_subscription(subscription)
        expect(result).to eq('identity_plus_v1_monthly')
      end
    end

    context 'when plan is not in catalog but in price metadata' do
      let(:subscription) do
        build_subscription(
          price_id: 'price_uncached',
          subscription_metadata: { 'plan_id' => 'subscription_level' },
          price_metadata: { 'plan_id' => 'price_level' },
        )
      end

      before do
        allow(Billing::Plan).to receive(:find_by_stripe_price_id)
          .with('price_uncached')
          .and_return(nil)
      end

      it 'falls back to price metadata' do
        result = described_class.resolve_plan_id_from_subscription(subscription)
        expect(result).to eq('price_level')
      end
    end

    context 'when plan is only in subscription metadata' do
      let(:subscription) do
        build_subscription(
          price_id: 'price_uncached',
          subscription_metadata: { 'plan_id' => 'subscription_level' },
          price_metadata: {},
        )
      end

      before do
        allow(Billing::Plan).to receive(:find_by_stripe_price_id)
          .with('price_uncached')
          .and_return(nil)
      end

      it 'falls back to subscription metadata' do
        result = described_class.resolve_plan_id_from_subscription(subscription)
        expect(result).to eq('subscription_level')
      end
    end

    context 'when no plan can be resolved' do
      let(:subscription) do
        build_subscription(
          price_id: 'price_uncached',
          subscription_metadata: {},
          price_metadata: {},
        )
      end

      before do
        allow(Billing::Plan).to receive(:find_by_stripe_price_id)
          .with('price_uncached')
          .and_return(nil)
      end

      it 'returns nil' do
        result = described_class.resolve_plan_id_from_subscription(subscription)
        expect(result).to be_nil
      end
    end
  end

  describe '.valid_plan_id?' do
    it 'returns true for free plans' do
      expect(described_class.valid_plan_id?('free')).to be true
      expect(described_class.valid_plan_id?('free_v1')).to be true
    end

    it 'returns false for empty plan_id' do
      expect(described_class.valid_plan_id?('')).to be false
      expect(described_class.valid_plan_id?(nil)).to be false
    end

    context 'with cached plan' do
      let(:mock_plan) { double('Plan', exists?: true) }

      before do
        allow(Billing::Plan).to receive(:load).with('identity_plus_v1').and_return(mock_plan)
      end

      it 'returns true if plan exists in cache' do
        expect(described_class.valid_plan_id?('identity_plus_v1')).to be true
      end
    end

    context 'with uncached plan but in config' do
      before do
        allow(Billing::Plan).to receive(:load).with('config_plan').and_return(nil)
        allow(Onetime).to receive(:conf).and_return({
          'billing' => {
            'plans' => { 'config_plan' => { 'name' => 'Config Plan' } },
          },
        })
      end

      it 'returns true if plan exists in config' do
        expect(described_class.valid_plan_id?('config_plan')).to be true
      end
    end

    context 'with completely invalid plan' do
      before do
        allow(Billing::Plan).to receive(:load).with('invalid_plan').and_return(nil)
        allow(Onetime).to receive(:conf).and_return({
          'billing' => { 'plans' => {} },
        })
      end

      it 'returns false for unknown plan' do
        expect(described_class.valid_plan_id?('invalid_plan')).to be false
      end
    end
  end

  describe '.compute_sync_status' do
    context 'with no billing data' do
      before do
        allow(mock_org).to receive(:planid).and_return('')
        allow(mock_org).to receive(:stripe_subscription_id).and_return('')
        allow(mock_org).to receive(:subscription_status).and_return('')
      end

      it 'returns unknown' do
        expect(described_class.compute_sync_status(mock_org)).to eq('unknown')
      end
    end

    context 'with active subscription and paid plan' do
      before do
        allow(mock_org).to receive(:planid).and_return('identity_plus_v1')
        allow(mock_org).to receive(:stripe_subscription_id).and_return('sub_123')
        allow(mock_org).to receive(:subscription_status).and_return('active')
      end

      it 'returns synced' do
        expect(described_class.compute_sync_status(mock_org)).to eq('synced')
      end
    end

    context 'with trialing subscription and paid plan' do
      before do
        allow(mock_org).to receive(:planid).and_return('identity_plus_v1')
        allow(mock_org).to receive(:stripe_subscription_id).and_return('sub_123')
        allow(mock_org).to receive(:subscription_status).and_return('trialing')
      end

      it 'returns synced' do
        expect(described_class.compute_sync_status(mock_org)).to eq('synced')
      end
    end

    context 'with no subscription and free plan' do
      before do
        allow(mock_org).to receive(:planid).and_return('free_v1')
        allow(mock_org).to receive(:stripe_subscription_id).and_return('')
        allow(mock_org).to receive(:subscription_status).and_return('')
      end

      it 'returns synced' do
        expect(described_class.compute_sync_status(mock_org)).to eq('synced')
      end
    end

    context 'with canceled subscription and free plan' do
      before do
        allow(mock_org).to receive(:planid).and_return('free_v1')
        allow(mock_org).to receive(:stripe_subscription_id).and_return('sub_123')
        allow(mock_org).to receive(:subscription_status).and_return('canceled')
      end

      it 'returns synced' do
        expect(described_class.compute_sync_status(mock_org)).to eq('synced')
      end
    end

    context 'with past_due subscription and paid plan' do
      before do
        allow(mock_org).to receive(:planid).and_return('identity_plus_v1')
        allow(mock_org).to receive(:stripe_subscription_id).and_return('sub_123')
        allow(mock_org).to receive(:subscription_status).and_return('past_due')
      end

      it 'returns synced (payment issue, not sync issue)' do
        expect(described_class.compute_sync_status(mock_org)).to eq('synced')
      end
    end

    context 'with active subscription but free plan' do
      before do
        allow(mock_org).to receive(:planid).and_return('free_v1')
        allow(mock_org).to receive(:stripe_subscription_id).and_return('sub_123')
        allow(mock_org).to receive(:subscription_status).and_return('active')
      end

      it 'returns potentially_stale' do
        expect(described_class.compute_sync_status(mock_org)).to eq('potentially_stale')
      end
    end

    context 'with no active subscription but paid plan' do
      before do
        allow(mock_org).to receive(:planid).and_return('identity_plus_v1')
        allow(mock_org).to receive(:stripe_subscription_id).and_return('sub_123')
        allow(mock_org).to receive(:subscription_status).and_return('canceled')
      end

      it 'returns potentially_stale' do
        expect(described_class.compute_sync_status(mock_org)).to eq('potentially_stale')
      end
    end
  end

  describe '.compute_sync_status_reason' do
    context 'when active subscription but free plan' do
      before do
        allow(mock_org).to receive(:planid).and_return('free_v1')
        allow(mock_org).to receive(:subscription_status).and_return('active')
      end

      it 'returns webhook miss explanation' do
        reason = described_class.compute_sync_status_reason(mock_org)
        expect(reason).to include('Active subscription')
        expect(reason).to include('webhook')
      end
    end

    context 'when paid plan but no active subscription' do
      before do
        allow(mock_org).to receive(:planid).and_return('identity_plus_v1')
        allow(mock_org).to receive(:subscription_status).and_return('canceled')
      end

      it 'returns downgrade explanation' do
        reason = described_class.compute_sync_status_reason(mock_org)
        expect(reason).to include('Paid plan')
        expect(reason).to include('downgrade')
      end
    end

    context 'when synced' do
      before do
        allow(mock_org).to receive(:planid).and_return('identity_plus_v1')
        allow(mock_org).to receive(:subscription_status).and_return('active')
      end

      it 'returns nil' do
        expect(described_class.compute_sync_status_reason(mock_org)).to be_nil
      end
    end
  end

  describe '.plans_match?' do
    it 'returns true for exact match' do
      expect(described_class.plans_match?('identity_plus_v1', 'identity_plus_v1')).to be true
    end

    it 'returns true when stripping interval suffix' do
      expect(described_class.plans_match?('identity_plus_v1', 'identity_plus_v1_monthly')).to be true
      expect(described_class.plans_match?('identity_plus_v1', 'identity_plus_v1_yearly')).to be true
    end

    it 'returns false for empty values' do
      expect(described_class.plans_match?('', 'identity_plus_v1')).to be false
      expect(described_class.plans_match?('identity_plus_v1', '')).to be false
    end

    it 'returns false for different plan versions' do
      expect(described_class.plans_match?('identity_plus', 'identity_plus_v1')).to be false
    end

    context 'when plan has plan_code in cache' do
      let(:mock_plan) { double('Plan', plan_code: 'identity_plus') }

      before do
        allow(Billing::Plan).to receive(:load).with('identity_plus_v1_monthly').and_return(mock_plan)
      end

      it 'matches against plan_code' do
        expect(described_class.plans_match?('identity_plus', 'identity_plus_v1_monthly')).to be true
      end
    end
  end

  describe '.normalize_plan_id' do
    it 'strips _monthly suffix' do
      expect(described_class.normalize_plan_id('identity_plus_v1_monthly')).to eq('identity_plus_v1')
    end

    it 'strips _yearly suffix' do
      expect(described_class.normalize_plan_id('identity_plus_v1_yearly')).to eq('identity_plus_v1')
    end

    it 'returns original if no interval suffix' do
      expect(described_class.normalize_plan_id('identity_plus_v1')).to eq('identity_plus_v1')
    end

    it 'handles nil gracefully' do
      expect(described_class.normalize_plan_id(nil)).to eq('')
    end
  end

  describe '.free_plan?' do
    it 'returns true for free plan IDs' do
      expect(described_class.free_plan?('free')).to be true
      expect(described_class.free_plan?('free_v1')).to be true
    end

    it 'returns true for empty plan ID' do
      expect(described_class.free_plan?('')).to be true
      expect(described_class.free_plan?(nil)).to be true
    end

    it 'returns false for paid plan IDs' do
      expect(described_class.free_plan?('identity_plus_v1')).to be false
    end
  end

  describe '.paid_plan?' do
    it 'returns false for free plan IDs' do
      expect(described_class.paid_plan?('free')).to be false
      expect(described_class.paid_plan?('free_v1')).to be false
    end

    it 'returns true for paid plan IDs' do
      expect(described_class.paid_plan?('identity_plus_v1')).to be true
    end
  end

  describe '.active_subscription_status?' do
    it 'returns true for active status' do
      expect(described_class.active_subscription_status?('active')).to be true
    end

    it 'returns true for trialing status' do
      expect(described_class.active_subscription_status?('trialing')).to be true
    end

    it 'returns false for other statuses' do
      expect(described_class.active_subscription_status?('past_due')).to be false
      expect(described_class.active_subscription_status?('canceled')).to be false
      expect(described_class.active_subscription_status?('unpaid')).to be false
    end
  end

  describe '.compare_billing_states' do
    let(:local_state) do
      {
        planid: 'identity_plus_v1',
        stripe_subscription_id: 'sub_123',
        subscription_status: 'active',
      }
    end

    context 'when stripe data is unavailable' do
      let(:stripe_state) { { available: false, reason: 'No subscription' } }

      it 'returns unable_to_compare verdict' do
        result = described_class.compare_billing_states(local_state, stripe_state)
        expect(result[:verdict]).to eq('unable_to_compare')
        expect(result[:match]).to be_nil
      end
    end

    context 'when states match' do
      let(:stripe_state) do
        {
          available: true,
          subscription: {
            id: 'sub_123',
            status: 'active',
            resolved_plan_id: 'identity_plus_v1_monthly',
          },
        }
      end

      it 'returns synced verdict' do
        result = described_class.compare_billing_states(local_state, stripe_state)
        expect(result[:verdict]).to eq('synced')
        expect(result[:match]).to be true
        expect(result[:issues]).to be_empty
      end
    end

    context 'when plan IDs mismatch' do
      let(:stripe_state) do
        {
          available: true,
          subscription: {
            id: 'sub_123',
            status: 'active',
            resolved_plan_id: 'different_plan',
          },
        }
      end

      it 'returns mismatch with high severity issue' do
        result = described_class.compare_billing_states(local_state, stripe_state)
        expect(result[:verdict]).to eq('mismatch_detected')
        expect(result[:match]).to be false
        expect(result[:issues].first[:field]).to eq('planid')
        expect(result[:issues].first[:severity]).to eq('high')
      end
    end

    context 'when subscription status mismatches' do
      let(:stripe_state) do
        {
          available: true,
          subscription: {
            id: 'sub_123',
            status: 'past_due',
            resolved_plan_id: 'identity_plus_v1',
          },
        }
      end

      it 'returns mismatch with medium severity issue' do
        result = described_class.compare_billing_states(local_state, stripe_state)
        expect(result[:verdict]).to eq('mismatch_detected')
        expect(result[:issues].first[:field]).to eq('subscription_status')
        expect(result[:issues].first[:severity]).to eq('medium')
      end
    end

    context 'when subscription IDs mismatch' do
      let(:stripe_state) do
        {
          available: true,
          subscription: {
            id: 'sub_different',
            status: 'active',
            resolved_plan_id: 'identity_plus_v1',
          },
        }
      end

      it 'returns mismatch with critical severity issue' do
        result = described_class.compare_billing_states(local_state, stripe_state)
        expect(result[:verdict]).to eq('mismatch_detected')
        expect(result[:issues].first[:field]).to eq('stripe_subscription_id')
        expect(result[:issues].first[:severity]).to eq('critical')
      end
    end
  end
end
