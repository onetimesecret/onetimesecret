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
      # Subscription with no valid plan_id in metadata — federated path reads nil from metadata
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

      # planid= is NOT called because metadata['plan_id'] is nil
      # and the guard `@org.planid = plan_id if plan_id` prevents the write
      expect(org).not_to receive(:planid=)

      expect(org).to receive(:save)

      described_class.call(org, subscription, owner: false)
    end

    it 'raises InvalidPlanMetadataError for a malformed federated plan_id' do
      # Interval-suffixed value is not a canonical family ID and must be rejected
      # before it is written onto org.planid.
      subscription = Stripe::Subscription.construct_from({
        id: 'sub_test_bad_meta',
        object: 'subscription',
        customer: 'cus_test_456',
        status: 'active',
        metadata: { 'plan_id' => 'identity_plus_v1_monthly' },
        items: {
          data: [{
            price: { id: 'price_eu_region', product: 'prod_test', metadata: {} },
            current_period_end: period_end,
          }],
        },
      })

      expect(org).not_to receive(:planid=)
      expect(org).not_to receive(:save)

      expect {
        described_class.call(org, subscription, owner: false)
      }.to raise_error(Billing::InvalidPlanMetadataError, /identity_plus_v1_monthly/)
    end

    it 'raises InvalidPlanMetadataError for a non-canonical (uppercase) plan_id' do
      subscription = Stripe::Subscription.construct_from({
        id: 'sub_test_upper_meta',
        object: 'subscription',
        customer: 'cus_test_456',
        status: 'active',
        metadata: { 'plan_id' => 'Identity_Plus_V1' },
        items: {
          data: [{
            price: { id: 'price_eu_region', product: 'prod_test', metadata: {} },
            current_period_end: period_end,
          }],
        },
      })

      expect(org).not_to receive(:planid=)

      expect {
        described_class.call(org, subscription, owner: false)
      }.to raise_error(Billing::InvalidPlanMetadataError)
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
        entitlements: double(to_a: %w[api_access manage_teams], size: 2),
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
          '[ApplySubscriptionToOrg] Materialized entitlements for org',
          hash_including(
            org_extid: 'on_test_org',
            planid: 'identity_plus_v1',
            entitlements_count: 4,
            source: 'cache',
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
          '[ApplySubscriptionToOrg] Materialized entitlements for org',
          hash_including(entitlements_count: 4, source: 'config'),
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

  # ============================================================================
  # .materialize_entitlements_for_org
  # ============================================================================

  describe Billing::Operations::MaterializeResult do
    let(:result) { described_class.new(status: :materialized, planid: 'p', entitlements_count: 2, source: :cache, reason: nil) }
    let(:skipped) { described_class.new(status: :skipped_no_plan, planid: nil, entitlements_count: nil, source: nil, reason: 'x') }

    it { expect(result.success?).to be true }
    it { expect(skipped.success?).to be false }
    it { expect(skipped.skipped?).to be true }
    it { expect(result.skipped?).to be false }
    it { expect(described_class.new(status: :skipped_fresh, planid: 'p', entitlements_count: 3, source: :cache, reason: 'r').skipped?).to be true }
  end

  # ============================================================================
  # Private helpers — focused unit tests
  # ============================================================================

  describe 'private helpers' do
    let(:plan) do
      instance_double(
        Billing::Plan,
        plan_id: 'identity_plus_v1',
        entitlements: double(size: 3),
      )
    end

    let(:fresh_org) do
      double('Organization',
        planid: 'identity_plus_v1',
        extid: 'on_helper_org',
        entitlements_materialized?: true,
        entitlements_stale?: false,
        materialize_entitlements_from_plan: true,
        materialize_entitlements_from_config: true,
        materialized_entitlements: materialized_set,
      )
    end

    # ------------------------------------------------------------------------
    # entitlements_fresh?
    # ------------------------------------------------------------------------
    describe '.entitlements_fresh?' do
      it 'returns true when materialized and not stale' do
        allow(fresh_org).to receive(:entitlements_materialized?).and_return(true)
        allow(fresh_org).to receive(:entitlements_stale?).with(plan).and_return(false)

        result = described_class.send(:entitlements_fresh?, fresh_org, plan)

        expect(result).to be true
      end

      it 'returns false when not materialized' do
        allow(fresh_org).to receive(:entitlements_materialized?).and_return(false)

        # entitlements_stale? must not be called — && short-circuits
        expect(fresh_org).not_to receive(:entitlements_stale?)

        result = described_class.send(:entitlements_fresh?, fresh_org, plan)

        expect(result).to be false
      end

      it 'returns false when materialized but stale' do
        allow(fresh_org).to receive(:entitlements_materialized?).and_return(true)
        allow(fresh_org).to receive(:entitlements_stale?).with(plan).and_return(true)

        result = described_class.send(:entitlements_fresh?, fresh_org, plan)

        expect(result).to be false
      end
    end

    # ------------------------------------------------------------------------
    # load_plan_for_materialize
    # ------------------------------------------------------------------------
    describe '.load_plan_for_materialize' do
      it 'returns [plan, :cache] on cache hit without calling load_from_config' do
        allow(Billing::Plan).to receive(:load).with('identity_plus_v1').and_return(plan)
        expect(Billing::Plan).not_to receive(:load_from_config)

        result_plan, source = described_class.send(:load_plan_for_materialize, 'identity_plus_v1')

        expect(result_plan).to eq(plan)
        expect(source).to eq(:cache)
      end

      it 'returns [config_data, :config] on cache miss + config hit' do
        config_data = { entitlements: %w[create_secrets api_access], limits: {} }

        allow(Billing::Plan).to receive(:load).with('identity_plus_v1').and_return(nil)
        allow(Billing::Plan).to receive(:load_from_config).with('identity_plus_v1').and_return(config_data)

        result_plan, source = described_class.send(:load_plan_for_materialize, 'identity_plus_v1')

        expect(result_plan).to eq(config_data)
        expect(source).to eq(:config)
      end

      it 'returns [nil, nil] when both cache and config miss' do
        allow(Billing::Plan).to receive(:load).with('unknown_plan').and_return(nil)
        allow(Billing::Plan).to receive(:load_from_config).with('unknown_plan').and_return(nil)

        result_plan, source = described_class.send(:load_plan_for_materialize, 'unknown_plan')

        expect(result_plan).to be_nil
        expect(source).to be_nil
      end
    end

    # ------------------------------------------------------------------------
    # execute_materialize
    # ------------------------------------------------------------------------
    describe '.execute_materialize' do
      it 'calls materialize_entitlements_from_plan when source is :cache' do
        expect(fresh_org).to receive(:materialize_entitlements_from_plan).with(plan)

        described_class.send(:execute_materialize, fresh_org, plan, :cache)
      end

      it 'calls materialize_entitlements_from_config when source is :config' do
        config_data = { entitlements: %w[create_secrets], limits: {} }
        expect(fresh_org).to receive(:materialize_entitlements_from_config).with(config_data)

        described_class.send(:execute_materialize, fresh_org, config_data, :config)
      end

      it 'returns a MaterializeResult with status :materialized' do
        allow(fresh_org).to receive(:materialize_entitlements_from_plan)

        result = described_class.send(:execute_materialize, fresh_org, plan, :cache)

        expect(result).to be_a(Billing::Operations::MaterializeResult)
        expect(result.status).to eq(:materialized)
      end

      it 'returns entitlements_count from org.materialized_entitlements.size' do
        allow(fresh_org).to receive(:materialize_entitlements_from_plan)

        result = described_class.send(:execute_materialize, fresh_org, plan, :cache)

        expect(result.entitlements_count).to eq(4) # materialized_set.size
      end

      it 'logs source as a string (not symbol)' do
        allow(fresh_org).to receive(:materialize_entitlements_from_plan)

        expect(OT).to receive(:info).with(
          '[ApplySubscriptionToOrg] Materialized entitlements for org',
          hash_including(source: 'cache'),
        )

        described_class.send(:execute_materialize, fresh_org, plan, :cache)
      end

      it 'logs source "config" as a string when source is :config' do
        config_data = { entitlements: [], limits: {} }
        allow(fresh_org).to receive(:materialize_entitlements_from_config)

        expect(OT).to receive(:info).with(
          '[ApplySubscriptionToOrg] Materialized entitlements for org',
          hash_including(source: 'config'),
        )

        described_class.send(:execute_materialize, fresh_org, config_data, :config)
      end
    end

    # ------------------------------------------------------------------------
    # Result builders
    # ------------------------------------------------------------------------
    describe '.skipped_no_plan_result' do
      subject(:result) { described_class.send(:skipped_no_plan_result) }

      it { expect(result.status).to eq(:skipped_no_plan) }
      it { expect(result.planid).to be_nil }
      it { expect(result.entitlements_count).to be_nil }
      it { expect(result.source).to be_nil }
      it { expect(result.reason).to eq('Organization has no planid') }
      it { expect(result.success?).to be false }
      it { expect(result.skipped?).to be true }
    end

    describe '.plan_not_found_result' do
      context 'when raise_on_miss is false' do
        before { allow(OT).to receive(:lw) }

        subject(:result) { described_class.send(:plan_not_found_result, fresh_org, 'identity_plus_v1', false) }

        it { expect(result.status).to eq(:plan_not_found) }
        it { expect(result.planid).to eq('identity_plus_v1') }
        it { expect(result.entitlements_count).to be_nil }
        it { expect(result.source).to be_nil }
        it { expect(result.reason).to eq("Plan 'identity_plus_v1' not in cache or config") }

        it 'logs a warning with org_extid and planid' do
          expect(OT).to receive(:lw).with(
            '[ApplySubscriptionToOrg] Plan not found, cannot materialize',
            hash_including(org_extid: 'on_helper_org', planid: 'identity_plus_v1'),
          )

          described_class.send(:plan_not_found_result, fresh_org, 'identity_plus_v1', false)
        end
      end

      context 'when raise_on_miss is true' do
        it 'raises PlanCacheMissError' do
          expect {
            described_class.send(:plan_not_found_result, fresh_org, 'identity_plus_v1', true)
          }.to raise_error(Billing::PlanCacheMissError)
        end

        it 'does not call OT.lw before raising' do
          expect(OT).not_to receive(:lw)

          expect {
            described_class.send(:plan_not_found_result, fresh_org, 'identity_plus_v1', true)
          }.to raise_error(Billing::PlanCacheMissError)
        end
      end
    end

    describe '.skipped_fresh_result' do
      subject(:result) { described_class.send(:skipped_fresh_result, fresh_org, 'identity_plus_v1', :cache) }

      it { expect(result.status).to eq(:skipped_fresh) }
      it { expect(result.planid).to eq('identity_plus_v1') }
      it { expect(result.source).to eq(:cache) }
      it { expect(result.entitlements_count).to eq(4) } # materialized_set.size
      it { expect(result.reason).to eq('Entitlements already materialized and not stale') }
      it { expect(result.skipped?).to be true }

      it 'reflects source :config when called with :config' do
        result = described_class.send(:skipped_fresh_result, fresh_org, 'identity_plus_v1', :config)

        expect(result.source).to eq(:config)
      end
    end

    describe '.would_materialize_result' do
      context 'when source is :cache' do
        it 'uses plan.entitlements.size for count' do
          result = described_class.send(:would_materialize_result, 'identity_plus_v1', plan, :cache)

          expect(result.status).to eq(:would_materialize)
          expect(result.planid).to eq('identity_plus_v1')
          expect(result.source).to eq(:cache)
          expect(result.entitlements_count).to eq(3) # plan.entitlements.size
          expect(result.reason).to be_nil
        end
      end

      context 'when source is :config' do
        it 'uses plan[:entitlements].size for count' do
          config_data = { entitlements: %w[create_secrets api_access manage_teams], limits: {} }

          result = described_class.send(:would_materialize_result, 'identity_plus_v1', config_data, :config)

          expect(result.entitlements_count).to eq(3)
          expect(result.source).to eq(:config)
        end

        it 'falls back to 0 when plan[:entitlements] is nil' do
          config_data = { limits: {} } # no :entitlements key

          result = described_class.send(:would_materialize_result, 'identity_plus_v1', config_data, :config)

          expect(result.entitlements_count).to eq(0)
        end
      end
    end
  end

  describe '.materialize_entitlements_for_org' do
    let(:cache_plan) do
      instance_double(
        Billing::Plan,
        plan_id: 'identity_plus_v1',
        entitlements: double(size: 2),
      )
    end

    let(:config_data) do
      { entitlements: %w[create_secrets api_access], limits: {} }
    end

    let(:fresh_org) do
      double('Organization',
        planid: 'identity_plus_v1',
        extid: 'on_fresh_org',
        entitlements_materialized?: true,
        entitlements_stale?: false,
        materialize_entitlements_from_plan: true,
        materialize_entitlements_from_config: true,
        materialized_entitlements: materialized_set,
      )
    end

    def stub_cache_hit
      allow(Billing::Plan).to receive(:load)
        .with('identity_plus_v1')
        .and_return(cache_plan)
    end

    def stub_cache_miss_config_hit
      allow(Billing::Plan).to receive(:load)
        .with('identity_plus_v1')
        .and_return(nil)
      allow(Billing::Plan).to receive(:load_from_config)
        .with('identity_plus_v1')
        .and_return(config_data)
    end

    def stub_both_miss
      allow(Billing::Plan).to receive(:load).and_return(nil)
      allow(Billing::Plan).to receive(:load_from_config).and_return(nil)
    end

    # ------------------------------------------------------------------
    # :skipped_no_plan
    # ------------------------------------------------------------------
    context 'when org has no planid' do
      let(:org_no_planid) do
        double('Organization', planid: '', extid: 'on_no_planid')
      end

      it 'returns :skipped_no_plan without calling Plan.load' do
        expect(Billing::Plan).not_to receive(:load)

        result = described_class.materialize_entitlements_for_org(org_no_planid)

        expect(result.status).to eq(:skipped_no_plan)
        expect(result.planid).to be_nil
        expect(result.entitlements_count).to be_nil
        expect(result.source).to be_nil
        expect(result.reason).to eq('Organization has no planid')
      end

      it 'does not call any materialize method' do
        expect(org_no_planid).not_to receive(:materialize_entitlements_from_plan)
        expect(org_no_planid).not_to receive(:materialize_entitlements_from_config)

        described_class.materialize_entitlements_for_org(org_no_planid)
      end
    end

    context 'when org planid is whitespace-only' do
      # planid.to_s.empty? is false for "   ", so the no-plan guard does not
      # fire. Plan.load("   ") returns nil, so the result is :plan_not_found.
      let(:org_whitespace_plan) do
        double('Organization', planid: '   ', extid: 'on_whitespace_org')
      end

      before do
        allow(Billing::Plan).to receive(:load).with('   ').and_return(nil)
        allow(Billing::Plan).to receive(:load_from_config).with('   ').and_return(nil)
      end

      it 'returns :plan_not_found (whitespace planid passes the empty? guard)' do
        result = described_class.materialize_entitlements_for_org(org_whitespace_plan)

        expect(result.status).to eq(:plan_not_found)
        expect(result.planid).to eq('   ')
      end
    end

    # ------------------------------------------------------------------
    # :plan_not_found
    # ------------------------------------------------------------------
    context 'when plan is in neither cache nor config' do
      before { stub_both_miss }

      it 'returns :plan_not_found with reason' do
        result = described_class.materialize_entitlements_for_org(org)

        expect(result.status).to eq(:plan_not_found)
        expect(result.planid).to eq('identity_plus_v1')
        expect(result.entitlements_count).to be_nil
        expect(result.source).to be_nil
        expect(result.reason).to eq("Plan 'identity_plus_v1' not in cache or config")
      end

      it 'logs a warning (does not raise)' do
        expect(OT).to receive(:lw).with(
          '[ApplySubscriptionToOrg] Plan not found, cannot materialize',
          hash_including(org_extid: 'on_test_org', planid: 'identity_plus_v1'),
        )

        described_class.materialize_entitlements_for_org(org)
      end

      it 'does not call any materialize method' do
        expect(org).not_to receive(:materialize_entitlements_from_plan)
        expect(org).not_to receive(:materialize_entitlements_from_config)

        described_class.materialize_entitlements_for_org(org)
      end

      context 'with raise_on_miss: true' do
        it 'raises PlanCacheMissError' do
          expect {
            described_class.materialize_entitlements_for_org(org, raise_on_miss: true)
          }.to raise_error(Billing::PlanCacheMissError)
        end

        it 'does NOT log a warning before raising' do
          expect(OT).not_to receive(:lw)

          expect {
            described_class.materialize_entitlements_for_org(org, raise_on_miss: true)
          }.to raise_error(Billing::PlanCacheMissError)
        end
      end
    end

    # ------------------------------------------------------------------
    # :skipped_fresh
    # ------------------------------------------------------------------
    context 'with skip_if_fresh: true when entitlements are current' do
      context 'plan from cache' do
        before { stub_cache_hit }

        it 'returns :skipped_fresh with source :cache and count from org' do
          allow(fresh_org).to receive(:entitlements_stale?).with(cache_plan).and_return(false)

          result = described_class.materialize_entitlements_for_org(fresh_org, skip_if_fresh: true)

          expect(result.status).to eq(:skipped_fresh)
          expect(result.source).to eq(:cache)
          expect(result.entitlements_count).to eq(4)
          expect(result.reason).to eq('Entitlements already materialized and not stale')
        end

        it 'does not materialize' do
          allow(fresh_org).to receive(:entitlements_stale?).with(cache_plan).and_return(false)

          expect(fresh_org).not_to receive(:materialize_entitlements_from_plan)
          expect(fresh_org).not_to receive(:materialize_entitlements_from_config)

          described_class.materialize_entitlements_for_org(fresh_org, skip_if_fresh: true)
        end
      end

      context 'plan from config' do
        before { stub_cache_miss_config_hit }

        it 'returns :skipped_fresh with source :config and count from org' do
          allow(fresh_org).to receive(:entitlements_stale?).with(config_data).and_return(false)

          result = described_class.materialize_entitlements_for_org(fresh_org, skip_if_fresh: true)

          expect(result.status).to eq(:skipped_fresh)
          expect(result.source).to eq(:config)
          expect(result.entitlements_count).to eq(4)
        end
      end
    end

    context 'with skip_if_fresh: true when entitlements ARE stale' do
      before { stub_cache_hit }

      it 'does NOT return :skipped_fresh — proceeds to materialize' do
        allow(fresh_org).to receive(:entitlements_stale?).with(cache_plan).and_return(true)

        result = described_class.materialize_entitlements_for_org(fresh_org, skip_if_fresh: true)

        expect(result.status).not_to eq(:skipped_fresh)
      end
    end

    # ------------------------------------------------------------------
    # :would_materialize (dry_run)
    # ------------------------------------------------------------------
    context 'with dry_run: true' do
      context 'plan from cache' do
        before { stub_cache_hit }

        it 'returns :would_materialize with count from plan (not org)' do
          result = described_class.materialize_entitlements_for_org(org, dry_run: true)

          expect(result.status).to eq(:would_materialize)
          expect(result.planid).to eq('identity_plus_v1')
          expect(result.source).to eq(:cache)
          expect(result.entitlements_count).to eq(2)
          expect(result.reason).to be_nil
        end

        it 'does not materialize' do
          expect(org).not_to receive(:materialize_entitlements_from_plan)
          expect(org).not_to receive(:materialize_entitlements_from_config)

          described_class.materialize_entitlements_for_org(org, dry_run: true)
        end
      end

      context 'plan from config' do
        before { stub_cache_miss_config_hit }

        it 'returns :would_materialize with count from config entitlements array' do
          result = described_class.materialize_entitlements_for_org(org, dry_run: true)

          expect(result.status).to eq(:would_materialize)
          expect(result.source).to eq(:config)
          expect(result.entitlements_count).to eq(2)
        end
      end
    end

    # ------------------------------------------------------------------
    # :materialized
    # ------------------------------------------------------------------
    context 'when materializing succeeds' do
      context 'plan from cache' do
        before { stub_cache_hit }

        it 'returns :materialized with source :cache and count from org' do
          allow(org).to receive(:materialize_entitlements_from_plan).with(cache_plan)

          result = described_class.materialize_entitlements_for_org(org)

          expect(result.status).to eq(:materialized)
          expect(result.source).to eq(:cache)
          expect(result.entitlements_count).to eq(4)
          expect(result.reason).to be_nil
          expect(result.success?).to be true
        end

        it 'calls materialize_entitlements_from_plan with the cached plan' do
          expect(org).to receive(:materialize_entitlements_from_plan).with(cache_plan)

          described_class.materialize_entitlements_for_org(org)
        end

        it 'logs the materialization event with string source' do
          allow(org).to receive(:materialize_entitlements_from_plan)

          expect(OT).to receive(:info).with(
            '[ApplySubscriptionToOrg] Materialized entitlements for org',
            hash_including(
              org_extid: 'on_test_org',
              planid: 'identity_plus_v1',
              entitlements_count: 4,
              source: 'cache',
            ),
          )

          described_class.materialize_entitlements_for_org(org)
        end
      end

      context 'plan from config' do
        before { stub_cache_miss_config_hit }

        it 'returns :materialized with source :config' do
          allow(org).to receive(:materialize_entitlements_from_config).with(config_data)

          result = described_class.materialize_entitlements_for_org(org)

          expect(result.status).to eq(:materialized)
          expect(result.source).to eq(:config)
          expect(result.entitlements_count).to eq(4)
        end

        it 'calls materialize_entitlements_from_config with config data' do
          expect(org).to receive(:materialize_entitlements_from_config).with(config_data)

          described_class.materialize_entitlements_for_org(org)
        end

        it 'logs with source "config"' do
          allow(org).to receive(:materialize_entitlements_from_config)

          expect(OT).to receive(:info).with(
            '[ApplySubscriptionToOrg] Materialized entitlements for org',
            hash_including(source: 'config'),
          )

          described_class.materialize_entitlements_for_org(org)
        end
      end
    end
  end
end
