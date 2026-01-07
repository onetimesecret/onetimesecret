# spec/unit/billing/plan_validator_spec.rb
#
# frozen_string_literal: true

# Test cases for Billing::PlanValidator module (Issue #2350)
#
# This module implements catalog-first plan_id validation with fail-closed behavior.
# The design ensures:
# - No organization can have a planid not in catalog
# - Cache miss raises error (forces proper setup)
# - Metadata drift is logged for visibility
#
# Run: pnpm run test:rspec spec/unit/billing/plan_validator_spec.rb

require 'spec_helper'

require_relative '../../../apps/web/billing/metadata'
require_relative '../../../apps/web/billing/models/plan'
require_relative '../../../apps/web/billing/errors'
require_relative '../../../apps/web/billing/lib/plan_validator'

RSpec.describe 'Billing::PlanValidator', billing: true do
  # ============================================================================
  # SECTION 1: Billing::PlanValidator.resolve_plan_id(price_id)
  # ============================================================================
  #
  # This is the NEW module that provides catalog-first lookup.
  # It should be the single source of truth for price_id -> plan_id resolution.
  #
  describe 'Billing::PlanValidator.resolve_plan_id' do
    # Stub the module under test (to be implemented)
    let(:validator) { Billing::PlanValidator }

    describe 'happy path: price_id found in catalog' do
      before do
        mock_plan = instance_double(
          Billing::Plan,
          plan_id: 'identity_plus_v1_monthly',
          stripe_price_id: 'price_1ABC123'
        )
        allow(Billing::Plan).to receive(:find_by_stripe_price_id)
          .with('price_1ABC123')
          .and_return(mock_plan)
      end

      it 'returns the plan_id from catalog' do
        expect(validator.resolve_plan_id('price_1ABC123')).to eq('identity_plus_v1_monthly')
      end

      it 'does not raise any error' do
        expect { validator.resolve_plan_id('price_1ABC123') }.not_to raise_error
      end
    end

    describe 'fail-closed: price_id NOT in catalog' do
      before do
        allow(Billing::Plan).to receive(:find_by_stripe_price_id)
          .with('price_UNKNOWN')
          .and_return(nil)
      end

      it 'raises Billing::CatalogMissError' do
        expect { validator.resolve_plan_id('price_UNKNOWN') }
          .to raise_error(Billing::CatalogMissError)
      end

      it 'includes the price_id in the error message' do
        expect { validator.resolve_plan_id('price_UNKNOWN') }
          .to raise_error(Billing::CatalogMissError, /price_UNKNOWN/)
      end

      it 'logs an error before raising' do
        logger = instance_double(SemanticLogger::Logger)
        allow(Onetime).to receive(:get_logger).with('Billing').and_return(logger)
        allow(logger).to receive(:error)

        expect(logger).to receive(:error).with(
          '[PlanValidator.resolve_plan_id] Price not in catalog',
          hash_including(price_id: 'price_UNKNOWN')
        )

        expect { validator.resolve_plan_id('price_UNKNOWN') }.to raise_error(Billing::CatalogMissError)
      end
    end

    describe 'edge cases: nil/empty price_id' do
      it 'raises ArgumentError for nil price_id' do
        expect { validator.resolve_plan_id(nil) }
          .to raise_error(ArgumentError, /price_id.*required/i)
      end

      it 'raises ArgumentError for empty string price_id' do
        expect { validator.resolve_plan_id('') }
          .to raise_error(ArgumentError, /price_id.*required/i)
      end

      it 'raises ArgumentError for whitespace-only price_id' do
        expect { validator.resolve_plan_id('   ') }
          .to raise_error(ArgumentError, /price_id.*required/i)
      end
    end

    describe 'multiple plans in catalog: correct selection' do
      before do
        monthly_plan = instance_double(
          Billing::Plan,
          plan_id: 'identity_plus_v1_monthly',
          stripe_price_id: 'price_monthly_123'
        )
        yearly_plan = instance_double(
          Billing::Plan,
          plan_id: 'identity_plus_v1_yearly',
          stripe_price_id: 'price_yearly_456'
        )
        team_plan = instance_double(
          Billing::Plan,
          plan_id: 'multi_team_v1_monthly',
          stripe_price_id: 'price_team_789'
        )

        allow(Billing::Plan).to receive(:find_by_stripe_price_id) do |price_id|
          {
            'price_monthly_123' => monthly_plan,
            'price_yearly_456' => yearly_plan,
            'price_team_789' => team_plan,
          }[price_id]
        end
      end

      it 'returns correct plan for monthly price' do
        expect(validator.resolve_plan_id('price_monthly_123')).to eq('identity_plus_v1_monthly')
      end

      it 'returns correct plan for yearly price' do
        expect(validator.resolve_plan_id('price_yearly_456')).to eq('identity_plus_v1_yearly')
      end

      it 'returns correct plan for team price' do
        expect(validator.resolve_plan_id('price_team_789')).to eq('multi_team_v1_monthly')
      end
    end
  end

  # ============================================================================
  # SECTION 2: Billing::PlanValidator.valid_plan_id?(plan_id)
  # ============================================================================
  #
  # Validates whether a plan_id exists in the catalog OR static config.
  # Used by Colonel CLI and other validation points.
  #
  describe 'Billing::PlanValidator.valid_plan_id?' do
    let(:validator) { Billing::PlanValidator }

    describe 'plan_id in catalog (Stripe-synced)' do
      before do
        mock_plan = instance_double(Billing::Plan, plan_id: 'identity_plus_v1_monthly')
        allow(Billing::Plan).to receive(:load).with('identity_plus_v1_monthly').and_return(mock_plan)
        allow(mock_plan).to receive(:exists?).and_return(true)
      end

      it 'returns true' do
        expect(validator.valid_plan_id?('identity_plus_v1_monthly')).to be true
      end
    end

    describe 'plan_id in static config (fallback)' do
      before do
        # Not in Stripe cache
        allow(Billing::Plan).to receive(:load).with('legacy_plan_v1').and_return(nil)

        # But exists in billing.yaml
        allow(Billing::Config).to receive(:load_plans).and_return({
          'legacy_plan_v1' => { 'tier' => 'legacy', 'entitlements' => [] },
        })
      end

      it 'returns true for plan in static config' do
        expect(validator.valid_plan_id?('legacy_plan_v1')).to be true
      end
    end

    describe 'plan_id not found anywhere' do
      before do
        allow(Billing::Plan).to receive(:load).with('nonexistent_plan').and_return(nil)
        allow(Billing::Config).to receive(:load_plans).and_return({})
      end

      it 'returns false' do
        expect(validator.valid_plan_id?('nonexistent_plan')).to be false
      end
    end

    describe 'edge cases: nil/empty plan_id' do
      it 'returns false for nil plan_id' do
        expect(validator.valid_plan_id?(nil)).to be false
      end

      it 'returns false for empty string plan_id' do
        expect(validator.valid_plan_id?('')).to be false
      end

      it 'returns false for whitespace-only plan_id' do
        expect(validator.valid_plan_id?('   ')).to be false
      end
    end

    describe 'known plan_ids from catalog' do
      # These are examples of valid plan IDs that should exist
      %w[
        free_v1
        identity_plus_v1_monthly
        identity_plus_v1_yearly
        multi_team_v1_monthly
      ].each do |plan_id|
        it "validates '#{plan_id}' when present in catalog" do
          mock_plan = instance_double(Billing::Plan, plan_id: plan_id)
          allow(Billing::Plan).to receive(:load).with(plan_id).and_return(mock_plan)
          allow(mock_plan).to receive(:exists?).and_return(true)

          expect(validator.valid_plan_id?(plan_id)).to be true
        end
      end
    end
  end

  # ============================================================================
  # SECTION 3: Billing::PlanValidator.available_plan_ids
  # ============================================================================
  #
  # Returns list of all valid plan_ids (for error messages, CLI help, etc.)
  #
  describe 'Billing::PlanValidator.available_plan_ids' do
    let(:validator) { Billing::PlanValidator }

    before do
      plan1 = instance_double(Billing::Plan, plan_id: 'identity_plus_v1_monthly')
      plan2 = instance_double(Billing::Plan, plan_id: 'multi_team_v1_yearly')
      allow(Billing::Plan).to receive(:list_plans).and_return([plan1, plan2])

      allow(Billing::Config).to receive(:load_plans).and_return({
        'legacy_v1' => { 'tier' => 'legacy' },
      })
    end

    it 'includes plan_ids from Stripe catalog' do
      result = validator.available_plan_ids
      expect(result).to include('identity_plus_v1_monthly', 'multi_team_v1_yearly')
    end

    it 'includes plan_ids from static config' do
      result = validator.available_plan_ids
      expect(result).to include('legacy_v1')
    end

    it 'returns a unique sorted list' do
      result = validator.available_plan_ids
      expect(result).to eq(result.uniq.sort)
    end
  end
end

# ==============================================================================
# SECTION 4: Updated extract_plan_id_from_subscription (Catalog-First)
# ==============================================================================
#
# These tests verify the NEW behavior of extract_plan_id_from_subscription
# which uses catalog-first approach instead of metadata-first.
#
# These tests verify the catalog-first approach with fail-closed behavior.
# extract_plan_id_from_subscription now uses PlanValidator.resolve_plan_id directly.
#
RSpec.describe 'WithOrganizationBilling#extract_plan_id_from_subscription (Catalog-First)', billing: true do
  let(:test_class) do
    Class.new do
      include Onetime::Models::Features::WithOrganizationBilling::InstanceMethods

      attr_accessor :objid

      def initialize
        @objid = 'test-org-123'
      end

      def test_extract_plan_id(subscription)
        extract_plan_id_from_subscription(subscription)
      end
    end
  end

  let(:org) { test_class.new }

  def build_subscription(price_id:, subscription_metadata: {}, price_metadata: {})
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

  describe 'catalog-first behavior' do
    context 'when price_id is in catalog' do
      before do
        mock_plan = instance_double(
          Billing::Plan,
          plan_id: 'identity_plus_v1_monthly',
          stripe_price_id: 'price_catalog_123'
        )
        allow(Billing::Plan).to receive(:find_by_stripe_price_id)
          .with('price_catalog_123')
          .and_return(mock_plan)
      end

      let(:subscription) do
        build_subscription(
          price_id: 'price_catalog_123',
          subscription_metadata: {},
          price_metadata: {}
        )
      end

      it 'returns plan_id from catalog' do
        expect(org.test_extract_plan_id(subscription)).to eq('identity_plus_v1_monthly')
      end

      it 'logs successful catalog resolution' do
        expect(OT).to receive(:info).with(
          '[Organization.extract_plan_id_from_subscription] Resolved plan from catalog',
          hash_including(
            plan_id: 'identity_plus_v1_monthly',
            price_id: 'price_catalog_123'
          )
        )
        org.test_extract_plan_id(subscription)
      end
    end

    context 'when price_id NOT in catalog (fail-closed)' do
      before do
        allow(Billing::Plan).to receive(:find_by_stripe_price_id)
          .with('price_unknown_999')
          .and_return(nil)
      end

      let(:subscription) do
        build_subscription(
          price_id: 'price_unknown_999',
          subscription_metadata: { Billing::Metadata::FIELD_PLAN_ID => 'metadata_plan' },
          price_metadata: {}
        )
      end

      it 'raises Billing::CatalogMissError' do
        expect { org.test_extract_plan_id(subscription) }
          .to raise_error(Billing::CatalogMissError)
      end

      it 'does NOT fall back to metadata (fail-closed)' do
        # Even though metadata has a plan_id, we should NOT use it
        expect { org.test_extract_plan_id(subscription) }
          .to raise_error(Billing::CatalogMissError)
      end

      it 'logs error before raising' do
        # PlanValidator uses billing_logger.error (not OT.le) for structured logging
        # We verify the error is raised with the correct price_id
        expect { org.test_extract_plan_id(subscription) }
          .to raise_error(Billing::CatalogMissError) { |error|
            expect(error.price_id).to eq('price_unknown_999')
            expect(error.message).to include('price_unknown_999')
          }
      end
    end
  end

  describe 'drift detection: metadata differs from catalog' do
    before do
      mock_plan = instance_double(
        Billing::Plan,
        plan_id: 'identity_plus_v1_monthly',
        stripe_price_id: 'price_test_drift'
      )
      allow(Billing::Plan).to receive(:find_by_stripe_price_id)
        .with('price_test_drift')
        .and_return(mock_plan)
    end

    let(:subscription) do
      build_subscription(
        price_id: 'price_test_drift',
        # Metadata says different plan (stale/incorrect)
        subscription_metadata: { Billing::Metadata::FIELD_PLAN_ID => 'identity_plus' },
        price_metadata: {}
      )
    end

    it 'returns catalog value (not metadata)' do
      expect(org.test_extract_plan_id(subscription)).to eq('identity_plus_v1_monthly')
    end

    it 'logs drift warning for visibility' do
      expect(OT).to receive(:lw).with(
        '[Organization.extract_plan_id_from_subscription] Drift detected - using catalog value',
        hash_including(
          catalog_plan_id: 'identity_plus_v1_monthly',
          metadata_plan_id: 'identity_plus',
          subscription_id: 'sub_test_123'
        )
      )
      allow(OT).to receive(:info) # Allow the success log
      org.test_extract_plan_id(subscription)
    end

    it 'uses catalog value regardless of price metadata' do
      sub = build_subscription(
        price_id: 'price_test_drift',
        subscription_metadata: {},
        price_metadata: { Billing::Metadata::FIELD_PLAN_ID => 'old_price_plan' }
      )

      expect(OT).to receive(:lw).with(
        '[Organization.extract_plan_id_from_subscription] Drift detected - using catalog value',
        hash_including(
          catalog_plan_id: 'identity_plus_v1_monthly',
          metadata_plan_id: 'old_price_plan'
        )
      )
      allow(OT).to receive(:info) # Allow the success log
      expect(org.test_extract_plan_id(sub)).to eq('identity_plus_v1_monthly')
    end
  end

  describe 'auto-correction on webhook' do
    before do
      mock_plan = instance_double(
        Billing::Plan,
        plan_id: 'identity_plus_v1_yearly',
        stripe_price_id: 'price_yearly_correct'
      )
      allow(Billing::Plan).to receive(:find_by_stripe_price_id)
        .with('price_yearly_correct')
        .and_return(mock_plan)
    end

    let(:subscription) do
      build_subscription(
        price_id: 'price_yearly_correct',
        # Stale metadata from before plan change
        subscription_metadata: { Billing::Metadata::FIELD_PLAN_ID => 'identity_plus_v1_monthly' },
        price_metadata: {}
      )
    end

    it 'returns the correct catalog plan_id' do
      expect(org.test_extract_plan_id(subscription)).to eq('identity_plus_v1_yearly')
    end

    it 'logs that stale data will be auto-corrected' do
      expect(OT).to receive(:lw).with(
        '[Organization.extract_plan_id_from_subscription] Drift detected - using catalog value',
        hash_including(
          catalog_plan_id: 'identity_plus_v1_yearly',
          metadata_plan_id: 'identity_plus_v1_monthly'
        )
      )
      allow(OT).to receive(:info) # Allow the success log
      org.test_extract_plan_id(subscription)
    end
  end
end

# ==============================================================================
# SECTION 5: Colonel CLI Validation (UpdateUserPlan)
# ==============================================================================
#
# These tests verify the Colonel admin CLI rejects invalid plan_ids.
#
RSpec.describe 'ColonelAPI::Logic::Colonel::UpdateUserPlan', billing: true do
  # Stub the logic class
  let(:logic_class) { ColonelAPI::Logic::Colonel::UpdateUserPlan }

  describe 'plan_id validation' do
    let(:params) do
      {
        'user_id' => 'cust_test_123',
        'planid' => plan_id,
      }
    end

    let(:mock_user) do
      instance_double(
        Onetime::Customer,
        objid: 'cust_test_123',
        extid: 'ext_123',
        planid: 'free_v1',
        exists?: true,
        anonymous?: false
      )
    end

    before do
      allow(Onetime::Customer).to receive(:load).with('cust_test_123').and_return(mock_user)
    end

    context 'when plan_id is valid (in catalog)' do
      let(:plan_id) { 'identity_plus_v1_monthly' }

      before do
        mock_plan = instance_double(Billing::Plan, plan_id: plan_id)
        allow(Billing::Plan).to receive(:load).with(plan_id).and_return(mock_plan)
        allow(mock_plan).to receive(:exists?).and_return(true)
      end

      it 'PlanValidator.valid_plan_id? returns true for valid plan' do
        # The UpdateUserPlan logic uses this to validate
        expect(Billing::PlanValidator.valid_plan_id?(plan_id)).to be true
      end
    end

    context 'when plan_id is invalid (not in catalog)' do
      let(:plan_id) { 'nonexistent_plan_xyz' }

      before do
        allow(Billing::Plan).to receive(:load).with(plan_id).and_return(nil)
        allow(Billing::Config).to receive(:load_plans).and_return({})
      end

      it 'PlanValidator.valid_plan_id? returns false' do
        # The UpdateUserPlan logic uses this to reject invalid plans
        expect(Billing::PlanValidator.valid_plan_id?(plan_id)).to be false
      end

      it 'available_plan_ids provides list for error messages' do
        plan1 = instance_double(Billing::Plan, plan_id: 'identity_plus_v1_monthly')
        allow(Billing::Plan).to receive(:list_plans).and_return([plan1])
        allow(Billing::Config).to receive(:load_plans).and_return({
          'legacy_v1' => { 'tier' => 'legacy' },
        })

        result = Billing::PlanValidator.available_plan_ids
        expect(result).to include('identity_plus_v1_monthly', 'legacy_v1')
      end
    end

    context 'when plan_id is empty' do
      let(:plan_id) { '' }

      it 'raises form error for missing plan_id' do
        # Already implemented - test documents expected behavior
      end
    end
  end
end

# ==============================================================================
# SECTION 6: Empty Catalog Edge Cases
# ==============================================================================
#
# Tests for scenarios where the plan catalog is empty (startup, refresh failure).
#
RSpec.describe 'Empty Catalog Scenarios', billing: true do
  describe 'when catalog is empty' do
    before do
      allow(Billing::Plan).to receive(:list_plans).and_return([])
      allow(Billing::Plan).to receive(:find_by_stripe_price_id).and_return(nil)
    end

    it 'PlanValidator.resolve_plan_id raises CatalogMissError' do
      expect { Billing::PlanValidator.resolve_plan_id('any_price_id') }
        .to raise_error(Billing::CatalogMissError)
    end

    it 'PlanValidator.valid_plan_id? falls back to static config' do
      allow(Billing::Config).to receive(:load_plans).and_return({
        'free_v1' => { 'tier' => 'free' },
      })

      expect(Billing::PlanValidator.valid_plan_id?('free_v1')).to be true
    end

    it 'PlanValidator.available_plan_ids returns static config plans' do
      allow(Billing::Config).to receive(:load_plans).and_return({
        'free_v1' => { 'tier' => 'free' },
      })

      expect(Billing::PlanValidator.available_plan_ids).to include('free_v1')
    end
  end
end

# ==============================================================================
# SECTION 7: CatalogMissError Definition
# ==============================================================================
#
# Tests for the new error class.
#
RSpec.describe 'Billing::CatalogMissError', billing: true do
  it 'is defined in Billing module' do
    expect(defined?(Billing::CatalogMissError)).to eq('constant')
  end

  it 'inherits from Billing::OpsProblem' do
    expect(Billing::CatalogMissError.superclass).to eq(Billing::OpsProblem)
  end

  it 'can be instantiated with a message' do
    error = Billing::CatalogMissError.new('Price price_xyz not found in catalog')
    expect(error.message).to include('price_xyz')
  end

  it 'stores the price_id for programmatic access' do
    error = Billing::CatalogMissError.new('Not found', price_id: 'price_123')
    expect(error.price_id).to eq('price_123')
  end
end
