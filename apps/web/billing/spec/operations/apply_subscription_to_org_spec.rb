# apps/web/billing/spec/operations/apply_subscription_to_org_spec.rb
#
# frozen_string_literal: true

# Unit tests for ApplySubscriptionToOrg shared operation.
#
# Verifies consistent field-setting across owner, federated, and
# migration codepaths.
#
# Run: pnpm run test:rspec apps/web/billing/spec/operations/apply_subscription_to_org_spec.rb

require 'spec_helper'
require 'billing/operations/apply_subscription_to_org'

RSpec.describe Billing::Operations::ApplySubscriptionToOrg, billing: true do
  let(:period_end) { (Time.now + 30 * 24 * 60 * 60).to_i }

  # materialized_entitlements set double — used in logging assertions
  let(:materialized_set) { double('materialized_entitlements', size: 4) }

  let(:org) do
    double('Organization',
      :subscription_status= => nil,
      :subscription_period_end= => nil,
      :planid= => nil,
      :complimentary= => nil,
      :stripe_subscription_id= => nil,
      :stripe_customer_id= => nil,
      planid: 'identity_plus_v1',
      extid: 'on_test_org',
      materialize_entitlements_from_plan: true,
      materialize_entitlements_from_config: true,
      materialized_entitlements: materialized_set,
      save: true,
    )
  end

  # Build subscription for owner path (uses catalog resolution via price_id)
  def build_subscription(status: 'active', metadata: {}, price_id: 'price_test')
    mock_plan = instance_double(Billing::Plan, plan_id: 'identity_plus_v1')
    allow(Billing::Plan).to receive(:find_by_stripe_price_id)
      .with(price_id)
      .and_return(mock_plan)

    Stripe::Subscription.construct_from({
      id: 'sub_test_123',
      object: 'subscription',
      customer: 'cus_test_456',
      status: status,
      metadata: metadata,
      items: {
        data: [{
          price: {
            id: price_id,
            product: 'prod_test',
            metadata: {},
          },
          current_period_end: period_end,
        }],
      },
    })
  end

  # Build subscription for federated path (uses metadata resolution)
  # Federated orgs receive subscriptions from other regions where the
  # price_id is not in the local catalog, so plan_id comes from metadata.
  def build_federated_subscription(status: 'active', plan_id: 'identity_plus_v1')
    # Mock valid_plan_id? to return true for the plan in metadata
    allow(Billing::PlanValidator).to receive(:valid_plan_id?)
      .with(plan_id)
      .and_return(true)

    Stripe::Subscription.construct_from({
      id: 'sub_test_123',
      object: 'subscription',
      customer: 'cus_test_456',
      status: status,
      metadata: { 'plan_id' => plan_id },
      items: {
        data: [{
          price: {
            id: 'price_eu_region',  # Cross-region price, not in local catalog
            product: 'prod_test',
            metadata: {},
          },
          current_period_end: period_end,
        }],
      },
    })
  end

  describe 'owner path' do
    it 'sets all fields including Stripe IDs' do
      subscription = build_subscription

      expect(org).to receive(:subscription_status=).with('active')
      expect(org).to receive(:subscription_period_end=).with(period_end.to_s)
      expect(org).to receive(:planid=).with('identity_plus_v1')
      expect(org).to receive(:stripe_subscription_id=).with('sub_test_123')
      expect(org).to receive(:stripe_customer_id=).with('cus_test_456')
      expect(org).to receive(:complimentary=).with(nil)
      expect(org).to receive(:save)

      described_class.call(org, subscription, owner: true)
    end

    it 'sets complimentary when metadata has complimentary=true' do
      subscription = build_subscription(
        metadata: { Billing::Metadata::FIELD_COMPLIMENTARY => 'true' }
      )

      expect(org).to receive(:complimentary=).with('true')

      described_class.call(org, subscription, owner: true)
    end

    it 'does not set planid when subscription items have no price' do
      subscription = Stripe::Subscription.construct_from({
        id: 'sub_test_no_price',
        object: 'subscription',
        customer: 'cus_test_456',
        status: 'active',
        metadata: {},
        items: { data: [] },
      })

      # Status and complimentary are still applied (they run before plan_id logic)
      expect(org).to receive(:subscription_status=).with('active')
      expect(org).to receive(:complimentary=).with(nil)

      # Plan ID is NOT set because price_id is nil (early return guard)
      expect(org).not_to receive(:planid=)

      expect(org).to receive(:save)

      described_class.call(org, subscription, owner: true)
    end

    it 'raises CatalogMissError when price_id is not in catalog' do
      unknown_price_id = 'price_not_in_catalog'

      # Allow the catalog lookup to fall through to real behavior (raises)
      allow(Billing::Plan).to receive(:find_by_stripe_price_id)
        .with(unknown_price_id)
        .and_return(nil)

      subscription = Stripe::Subscription.construct_from({
        id: 'sub_test_unknown',
        object: 'subscription',
        customer: 'cus_test_456',
        status: 'active',
        metadata: {},
        items: {
          data: [{
            price: {
              id: unknown_price_id,
              product: 'prod_test',
              metadata: {},
            },
            current_period_end: period_end,
          }],
        },
      })

      expect {
        described_class.call(org, subscription, owner: true)
      }.to raise_error(Billing::CatalogMissError)
    end
  end

  describe 'federated path' do
    it 'sets status and plan but NOT Stripe IDs' do
      # Federated path uses metadata-based resolution (not catalog)
      subscription = build_federated_subscription

      expect(org).to receive(:subscription_status=).with('active')
      expect(org).to receive(:planid=).with('identity_plus_v1')
      expect(org).not_to receive(:stripe_subscription_id=)
      expect(org).not_to receive(:stripe_customer_id=)
      expect(org).to receive(:save)

      described_class.call(org, subscription, owner: false)
    end

    it 'preserves existing planid when metadata resolution returns nil' do
      # Subscription with no valid plan_id in metadata — resolve_plan_id_for_federation returns nil
      allow(Billing::PlanValidator).to receive(:valid_plan_id?).and_return(false)

      subscription = Stripe::Subscription.construct_from({
        id: 'sub_test_no_meta',
        object: 'subscription',
        customer: 'cus_test_456',
        status: 'active',
        metadata: {},
        items: {
          data: [{
            price: {
              id: 'price_eu_region',
              product: 'prod_test',
              metadata: {},
            },
            current_period_end: period_end,
          }],
        },
      })

      # Status fields are still applied
      expect(org).to receive(:subscription_status=).with('active')

      # planid= is NOT called because resolve_plan_id_for_federation returns nil
      # and the guard `@org.planid = plan_id if plan_id` prevents the write
      expect(org).not_to receive(:planid=)

      expect(org).to receive(:save)

      described_class.call(org, subscription, owner: false)
    end
  end

  describe 'planid_override' do
    it 'uses override instead of catalog resolution' do
      subscription = build_subscription(price_id: 'price_unknown')
      # No catalog mock for price_unknown — would raise without override

      expect(org).to receive(:planid=).with('identity_plus_v1')

      described_class.call(org, subscription, owner: true,
        planid_override: 'identity_plus_v1')
    end
  end

  describe 'complimentary clearing' do
    it 'clears complimentary when metadata does not have the field' do
      subscription = build_subscription(metadata: {})

      expect(org).to receive(:complimentary=).with(nil)

      described_class.call(org, subscription, owner: true)
    end

    it 'clears complimentary when metadata has complimentary=false' do
      subscription = build_subscription(
        metadata: { Billing::Metadata::FIELD_COMPLIMENTARY => 'false' }
      )

      expect(org).to receive(:complimentary=).with(nil)

      described_class.call(org, subscription, owner: true)
    end
  end

  describe 'save: false' do
    it 'applies fields but does not call save' do
      # Uses federated path (owner: false) with metadata-based resolution
      subscription = build_federated_subscription

      expect(org).to receive(:subscription_status=).with('active')
      expect(org).to receive(:planid=).with('identity_plus_v1')
      expect(org).not_to receive(:save)

      described_class.call(org, subscription, owner: false, save: false)
    end
  end

  describe 'apply_status_fields with nil period_end' do
    it 'does not set subscription_period_end when items are empty' do
      subscription = Stripe::Subscription.construct_from({
        id: 'sub_test_empty_items',
        object: 'subscription',
        customer: 'cus_test_456',
        status: 'past_due',
        metadata: {},
        items: { data: [] },
      })

      expect(org).to receive(:subscription_status=).with('past_due')

      # period_end is nil because items.data is empty — the guard
      # `if period_end` prevents subscription_period_end= from being called
      expect(org).not_to receive(:subscription_period_end=)

      expect(org).to receive(:save)

      described_class.call(org, subscription, owner: false)
    end
  end

  # ============================================================================
  # Materialization via .call (Phase 2 — #3134)
  # ============================================================================

  describe '#materialize_entitlements (called from .call)' do
    let(:cached_plan) do
      instance_double(
        Billing::Plan,
        plan_id: 'identity_plus_v1',
        entitlements: double(to_a: %w[api_access manage_teams]),
        limits: double(hgetall: { 'teams.max' => '5' }),
      )
    end

    context 'when plan exists in Redis cache' do
      before do
        allow(Billing::Plan).to receive(:find_by_stripe_price_id)
          .and_return(instance_double(Billing::Plan, plan_id: 'identity_plus_v1'))
        allow(Billing::Plan).to receive(:load)
          .with('identity_plus_v1')
          .and_return(cached_plan)
      end

      it 'calls materialize_entitlements_from_plan with the cached plan' do
        subscription = build_subscription
        expect(org).to receive(:materialize_entitlements_from_plan).with(cached_plan)

        described_class.call(org, subscription, owner: true)
      end

      it 'logs entitlements_count from materialized set' do
        subscription = build_subscription
        allow(org).to receive(:materialize_entitlements_from_plan)

        expect(OT).to receive(:info).with(
          '[ApplySubscriptionToOrg] Materialized entitlements from cached plan',
          hash_including(
            org_extid: 'on_test_org',
            planid: 'identity_plus_v1',
            entitlements_count: 4,
          ),
        )

        described_class.call(org, subscription, owner: true)
      end
    end

    context 'when plan is config-only (not in Redis cache)' do
      let(:config_plan_data) do
        {
          entitlements: %w[create_secrets api_access],
          limits: { 'secret_lifetime.max' => '1209600' },
        }
      end

      before do
        allow(Billing::Plan).to receive(:find_by_stripe_price_id)
          .and_return(instance_double(Billing::Plan, plan_id: 'identity_plus_v1'))
        allow(Billing::Plan).to receive(:load)
          .with('identity_plus_v1')
          .and_return(nil)
        allow(Billing::Plan).to receive(:load_from_config)
          .with('identity_plus_v1')
          .and_return(config_plan_data)
      end

      it 'calls materialize_entitlements_from_config with config data' do
        subscription = build_subscription
        expect(org).to receive(:materialize_entitlements_from_config).with(config_plan_data)

        described_class.call(org, subscription, owner: true)
      end

      it 'logs entitlements_count from materialized set' do
        subscription = build_subscription

        expect(OT).to receive(:info).with(
          '[ApplySubscriptionToOrg] Materialized entitlements from config plan',
          hash_including(entitlements_count: 4),
        )

        described_class.call(org, subscription, owner: true)
      end
    end

    context 'when planid is in neither cache nor config' do
      before do
        allow(Billing::Plan).to receive(:find_by_stripe_price_id)
          .and_return(instance_double(Billing::Plan, plan_id: 'identity_plus_v1'))
        allow(Billing::Plan).to receive(:load)
          .with('identity_plus_v1')
          .and_return(nil)
        allow(Billing::Plan).to receive(:load_from_config)
          .with('identity_plus_v1')
          .and_return(nil)
      end

      it 'raises PlanCacheMissError (fail-closed)' do
        subscription = build_subscription

        expect {
          described_class.call(org, subscription, owner: true)
        }.to raise_error(Billing::PlanCacheMissError)
      end
    end

    context 'when planid is empty after applying' do
      let(:org_no_plan) do
        double('Organization',
          :subscription_status= => nil,
          :subscription_period_end= => nil,
          :planid= => nil,
          :complimentary= => nil,
          :stripe_subscription_id= => nil,
          :stripe_customer_id= => nil,
          planid: nil,
          extid: 'on_no_plan_org',
          materialized_entitlements: materialized_set,
          save: true,
        )
      end

      it 'skips materialization when planid is nil' do
        subscription = Stripe::Subscription.construct_from({
          id: 'sub_no_plan',
          object: 'subscription',
          customer: 'cus_test',
          status: 'active',
          metadata: {},
          items: { data: [] },
        })

        expect(org_no_plan).not_to receive(:materialize_entitlements_from_plan)
        expect(org_no_plan).not_to receive(:materialize_entitlements_from_config)

        described_class.call(org_no_plan, subscription, owner: true)
      end
    end
  end

  # ============================================================================
  # Materialization via .apply_free_tier (cancel path)
  # ============================================================================

  describe '.apply_free_tier materialization' do
    let(:free_tier_org) do
      double('Organization',
        :subscription_status= => nil,
        :planid= => nil,
        :complimentary= => nil,
        :subscription_period_end= => nil,
        :stripe_subscription_id= => nil,
        extid: 'on_cancel_org',
        materialize_entitlements_from_config: true,
        materialized_entitlements: materialized_set,
        save: true,
      )
    end

    let(:free_config) do
      {
        entitlements: %w[create_secrets view_receipt api_access],
        limits: { 'secret_lifetime.max' => '1209600' },
      }
    end

    context 'when free_v1 is in billing.yaml config' do
      before do
        allow(Billing::Plan).to receive(:load_from_config)
          .with(Billing::Metadata::FREE_PLAN_ID)
          .and_return(free_config)
      end

      it 'calls materialize_entitlements_from_config with free plan config' do
        expect(free_tier_org).to receive(:materialize_entitlements_from_config).with(free_config)

        described_class.apply_free_tier(free_tier_org, owner: true)
      end

      it 'logs the materialization event' do
        allow(free_tier_org).to receive(:materialize_entitlements_from_config)

        expect(OT).to receive(:info).with(
          '[ApplySubscriptionToOrg] Materialized free tier entitlements',
          hash_including(
            org_extid: 'on_cancel_org',
            planid: Billing::Metadata::FREE_PLAN_ID,
            entitlements_count: 4,
          ),
        )

        described_class.apply_free_tier(free_tier_org, owner: true)
      end
    end

    context 'when free_v1 is not in billing.yaml config' do
      before do
        allow(Billing::Plan).to receive(:load_from_config)
          .with(Billing::Metadata::FREE_PLAN_ID)
          .and_return(nil)
      end

      it 'does NOT raise — logs a warning instead' do
        expect {
          described_class.apply_free_tier(free_tier_org, owner: true)
        }.not_to raise_error
      end

      it 'logs a warning with org_extid and planid' do
        expect(OT).to receive(:lw).with(
          '[ApplySubscriptionToOrg] Free plan not in config, cannot materialize',
          hash_including(
            org_extid: 'on_cancel_org',
            planid: Billing::Metadata::FREE_PLAN_ID,
          ),
        )

        described_class.apply_free_tier(free_tier_org, owner: true)
      end

      it 'does NOT call materialize_entitlements_from_config' do
        expect(free_tier_org).not_to receive(:materialize_entitlements_from_config)

        described_class.apply_free_tier(free_tier_org, owner: true)
      end
    end
  end
end
