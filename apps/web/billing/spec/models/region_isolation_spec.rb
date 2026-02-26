# apps/web/billing/spec/models/region_isolation_spec.rb
#
# frozen_string_literal: true

# Tests for billing region isolation fixes (Issue #2554)
#
# Covers:
#   - RegionNormalizer unit tests (foundation)
#   - Bug #3 (P1): upsert_config_only_plans region normalization
#   - Bug #4 (P2): load_all_from_config region filtering
#
# CLI-related tests (Bugs #1 and #2) are in spec/cli/catalog_push_region_spec.rb
# since they require the CLI infrastructure to be loaded first.
#
# Run: bundle exec rspec apps/web/billing/spec/models/region_isolation_spec.rb

require_relative '../support/billing_spec_helper'
require_relative '../../models/plan'
require_relative '../../region_normalizer'

# ==============================================================================
# SECTION 1: RegionNormalizer (foundation for all fixes)
# ==============================================================================

RSpec.describe Billing::RegionNormalizer, type: :billing do
  describe '.normalize' do
    it 'returns nil for nil input' do
      expect(described_class.normalize(nil)).to be_nil
    end

    it 'returns nil for empty string' do
      expect(described_class.normalize('')).to be_nil
    end

    it 'returns nil for whitespace-only string' do
      expect(described_class.normalize('  ')).to be_nil
    end

    it 'upcases lowercase region codes' do
      expect(described_class.normalize('nz')).to eq('NZ')
    end

    it 'preserves already-upcased region codes' do
      expect(described_class.normalize('NZ')).to eq('NZ')
    end

    it 'strips leading and trailing whitespace' do
      expect(described_class.normalize(' nz ')).to eq('NZ')
    end

    it 'handles mixed case' do
      expect(described_class.normalize('Eu')).to eq('EU')
    end
  end

  describe '.match?' do
    it 'matches case-insensitively' do
      expect(described_class.match?('nz', 'NZ')).to be true
    end

    it 'matches identical values' do
      expect(described_class.match?('NZ', 'NZ')).to be true
    end

    it 'passes through when first arg is nil' do
      expect(described_class.match?(nil, 'NZ')).to be true
    end

    it 'passes through when second arg is nil' do
      expect(described_class.match?('NZ', nil)).to be true
    end

    it 'passes through when both args are nil' do
      expect(described_class.match?(nil, nil)).to be true
    end

    it 'passes through when first arg is blank' do
      expect(described_class.match?('', 'NZ')).to be true
    end

    it 'rejects different regions' do
      expect(described_class.match?('NZ', 'US')).to be false
    end

    it 'rejects different regions case-insensitively' do
      expect(described_class.match?('nz', 'us')).to be false
    end
  end
end

# ==============================================================================
# SECTION 2: upsert_config_only_plans region normalization (Bug #3)
# ==============================================================================

RSpec.describe 'Billing::Plan.upsert_config_only_plans region normalization', type: :billing do
  before do
    Billing::Plan.clear_cache
  end

  after do
    Billing::Plan.clear_cache
  end

  describe 'plan.region assignment' do
    it 'normalizes lowercase region from config to uppercase' do
      plans_hash = {
        'free_test' => {
          'name' => 'Free Test',
          'tier' => 'free',
          'tenancy' => 'multi',
          'region' => 'nz',
          'display_order' => 0,
          'show_on_plans_page' => true,
          'description' => 'Test plan',
          'entitlements' => ['create_secrets'],
          'limits' => {},
          'features' => [],
          'prices' => [],
        },
      }

      allow(OT.billing_config).to receive(:plans).and_return(plans_hash)
      allow(OT.billing_config).to receive(:region).and_return('NZ')

      Billing::Plan.upsert_config_only_plans

      plan = Billing::Plan.load('free_test')
      expect(plan).not_to be_nil
      expect(plan.region).to eq('NZ')
    end

    it 'falls back to billing_config.region when plan region is nil' do
      plans_hash = {
        'free_test' => {
          'name' => 'Free Test',
          'tier' => 'free',
          'tenancy' => 'multi',
          'region' => nil,
          'display_order' => 0,
          'show_on_plans_page' => true,
          'description' => 'Test plan',
          'entitlements' => ['create_secrets'],
          'limits' => {},
          'features' => [],
          'prices' => [],
        },
      }

      allow(OT.billing_config).to receive(:plans).and_return(plans_hash)
      allow(OT.billing_config).to receive(:region).and_return('EU')

      Billing::Plan.upsert_config_only_plans

      plan = Billing::Plan.load('free_test')
      expect(plan).not_to be_nil
      expect(plan.region).to eq('EU')
    end

    it 'falls back to billing_config.region when plan region is empty string' do
      plans_hash = {
        'free_test' => {
          'name' => 'Free Test',
          'tier' => 'free',
          'tenancy' => 'multi',
          'region' => '',
          'display_order' => 0,
          'show_on_plans_page' => true,
          'description' => 'Test plan',
          'entitlements' => [],
          'limits' => {},
          'features' => [],
          'prices' => [],
        },
      }

      allow(OT.billing_config).to receive(:plans).and_return(plans_hash)
      allow(OT.billing_config).to receive(:region).and_return('CA')

      Billing::Plan.upsert_config_only_plans

      plan = Billing::Plan.load('free_test')
      expect(plan).not_to be_nil
      expect(plan.region).to eq('CA')
    end

    it 'uses explicit region when present and valid' do
      plans_hash = {
        'free_test' => {
          'name' => 'Free Test',
          'tier' => 'free',
          'tenancy' => 'multi',
          'region' => 'US',
          'display_order' => 0,
          'show_on_plans_page' => true,
          'description' => 'Test plan',
          'entitlements' => [],
          'limits' => {},
          'features' => [],
          'prices' => [],
        },
      }

      allow(OT.billing_config).to receive(:plans).and_return(plans_hash)
      allow(OT.billing_config).to receive(:region).and_return('EU')

      Billing::Plan.upsert_config_only_plans

      plan = Billing::Plan.load('free_test')
      expect(plan).not_to be_nil
      # Explicit 'US' takes precedence over billing_config.region 'EU'
      expect(plan.region).to eq('US')
    end
  end
end

# ==============================================================================
# SECTION 3: load_all_from_config region filtering (Bug #4)
# ==============================================================================

RSpec.describe 'Billing::Plan.load_all_from_config region filtering', type: :billing do
  before do
    Billing::Plan.clear_cache
  end

  after do
    Billing::Plan.clear_cache
  end

  let(:nz_plan) do
    {
      'name' => 'NZ Plan',
      'tier' => 'plus',
      'tenancy' => 'multi',
      'region' => 'NZ',
      'display_order' => 1,
      'show_on_plans_page' => true,
      'description' => 'NZ-only plan',
      'entitlements' => ['create_secrets'],
      'limits' => { 'teams' => 1 },
      'features' => [],
      'prices' => [
        { 'interval' => 'month', 'amount' => 1200, 'currency' => 'nzd' },
      ],
    }
  end

  let(:eu_plan) do
    {
      'name' => 'EU Plan',
      'tier' => 'plus',
      'tenancy' => 'multi',
      'region' => 'EU',
      'display_order' => 2,
      'show_on_plans_page' => true,
      'description' => 'EU-only plan',
      'entitlements' => ['create_secrets'],
      'limits' => { 'teams' => 1 },
      'features' => [],
      'prices' => [
        { 'interval' => 'month', 'amount' => 1000, 'currency' => 'eur' },
      ],
    }
  end

  let(:us_plan) do
    {
      'name' => 'US Plan',
      'tier' => 'plus',
      'tenancy' => 'multi',
      'region' => 'US',
      'display_order' => 3,
      'show_on_plans_page' => true,
      'description' => 'US-only plan',
      'entitlements' => ['create_secrets'],
      'limits' => { 'teams' => 1 },
      'features' => [],
      'prices' => [
        { 'interval' => 'month', 'amount' => 1000, 'currency' => 'usd' },
      ],
    }
  end

  let(:multi_region_plans) do
    {
      'nz_plan_v1' => nz_plan,
      'eu_plan_v1' => eu_plan,
      'us_plan_v1' => us_plan,
    }
  end

  describe 'with configured region "NZ"' do
    before do
      allow(OT.billing_config).to receive(:plans).and_return(multi_region_plans)
      allow(OT.billing_config).to receive(:region).and_return('NZ')
    end

    it 'only loads NZ plans' do
      count = Billing::Plan.load_all_from_config
      expect(count).to eq(1)

      plan = Billing::Plan.load('nz_plan_v1_monthly')
      expect(plan).not_to be_nil
      expect(plan.region).to eq('NZ')
    end

    it 'skips EU and US plans' do
      Billing::Plan.load_all_from_config

      expect(Billing::Plan.load('eu_plan_v1_monthly')).to be_nil
      expect(Billing::Plan.load('us_plan_v1_monthly')).to be_nil
    end
  end

  describe 'with configured region "EU"' do
    before do
      allow(OT.billing_config).to receive(:plans).and_return(multi_region_plans)
      allow(OT.billing_config).to receive(:region).and_return('EU')
    end

    it 'only loads EU plans' do
      count = Billing::Plan.load_all_from_config
      expect(count).to eq(1)
    end

    it 'skips NZ and US plans' do
      Billing::Plan.load_all_from_config

      expect(Billing::Plan.load('nz_plan_v1_monthly')).to be_nil
      expect(Billing::Plan.load('us_plan_v1_monthly')).to be_nil
    end
  end

  describe 'with no configured region (nil)' do
    before do
      allow(OT.billing_config).to receive(:plans).and_return(multi_region_plans)
      allow(OT.billing_config).to receive(:region).and_return(nil)
    end

    it 'loads all plans (pass-through)' do
      count = Billing::Plan.load_all_from_config
      expect(count).to eq(3)
    end

    it 'includes plans from all regions' do
      Billing::Plan.load_all_from_config

      expect(Billing::Plan.load('nz_plan_v1_monthly')).not_to be_nil
      expect(Billing::Plan.load('eu_plan_v1_monthly')).not_to be_nil
      expect(Billing::Plan.load('us_plan_v1_monthly')).not_to be_nil
    end
  end

  describe 'case-insensitive region matching' do
    let(:lowercase_region_plan) do
      {
        'name' => 'NZ Plan Lower',
        'tier' => 'plus',
        'tenancy' => 'multi',
        'region' => 'nz',  # lowercase in config
        'display_order' => 1,
        'show_on_plans_page' => true,
        'description' => 'NZ plan with lowercase region',
        'entitlements' => ['create_secrets'],
        'limits' => {},
        'features' => [],
        'prices' => [
          { 'interval' => 'month', 'amount' => 1200, 'currency' => 'nzd' },
        ],
      }
    end

    before do
      allow(OT.billing_config).to receive(:plans).and_return({ 'nz_lower_v1' => lowercase_region_plan })
      allow(OT.billing_config).to receive(:region).and_return('NZ')  # uppercase filter
    end

    it 'matches lowercase plan region against uppercase configured region' do
      count = Billing::Plan.load_all_from_config
      expect(count).to eq(1)

      plan = Billing::Plan.load('nz_lower_v1_monthly')
      expect(plan).not_to be_nil
    end
  end
end
