# spec/unit/onetime/models/features/with_entitlements_ttl_env_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'erb'
require 'yaml'

# Unit tests for WithEntitlements TTL Environment Variable Support
#
# Tests the parse_ttl_env method and free_tier_limits dynamic computation
# that allows Docker/self-hosted deployments to override TTL limits via
# environment variables.
#
# This provides upgrade continuity with PR #2393 from main branch.
# @see https://github.com/onetimesecret/onetimesecret/issues/2390
# @see https://github.com/onetimesecret/onetimesecret/issues/3111
#
RSpec.describe Onetime::Models::Features::WithEntitlements do
  describe '.parse_ttl_env' do
    let(:default_value) { 604_800 } # 7 days

    after do
      ENV.delete('TEST_TTL_VAR')
    end

    context 'when environment variable is not set' do
      it 'returns the default value' do
        result = described_class.parse_ttl_env('TEST_TTL_VAR', default_value)
        expect(result).to eq(default_value)
      end
    end

    context 'when environment variable is empty string' do
      before { ENV['TEST_TTL_VAR'] = '' }

      it 'returns the default value' do
        result = described_class.parse_ttl_env('TEST_TTL_VAR', default_value)
        expect(result).to eq(default_value)
      end
    end

    context 'when environment variable is whitespace only' do
      before { ENV['TEST_TTL_VAR'] = '   ' }

      it 'returns the default value' do
        result = described_class.parse_ttl_env('TEST_TTL_VAR', default_value)
        expect(result).to eq(default_value)
      end
    end

    context 'when environment variable is a valid integer' do
      before { ENV['TEST_TTL_VAR'] = '2592000' } # 30 days

      it 'returns the parsed integer value' do
        result = described_class.parse_ttl_env('TEST_TTL_VAR', default_value)
        expect(result).to eq(2_592_000)
      end
    end

    context 'when environment variable has leading/trailing whitespace' do
      before { ENV['TEST_TTL_VAR'] = '  1209600  ' } # 14 days with whitespace

      it 'returns the parsed integer value after trimming' do
        result = described_class.parse_ttl_env('TEST_TTL_VAR', default_value)
        expect(result).to eq(1_209_600)
      end
    end

    context 'when environment variable exceeds MAX_TTL' do
      before { ENV['TEST_TTL_VAR'] = '999999999' } # Way more than 365 days

      it 'caps the value at MAX_TTL (365 days)' do
        result = described_class.parse_ttl_env('TEST_TTL_VAR', default_value)
        expect(result).to eq(described_class::MAX_TTL)
        expect(result).to eq(365 * 24 * 60 * 60)
      end
    end

    context 'when environment variable is exactly MAX_TTL' do
      before { ENV['TEST_TTL_VAR'] = (365 * 24 * 60 * 60).to_s }

      it 'returns the MAX_TTL value' do
        result = described_class.parse_ttl_env('TEST_TTL_VAR', default_value)
        expect(result).to eq(described_class::MAX_TTL)
      end
    end

    context 'when environment variable is invalid (malformed string)' do
      before { ENV['TEST_TTL_VAR'] = '123abc' }

      it 'returns the default value' do
        result = described_class.parse_ttl_env('TEST_TTL_VAR', default_value)
        expect(result).to eq(default_value)
      end

      it 'logs a warning with env var name' do
        expect(OT).to receive(:lw).with(
          '[WithEntitlements] Invalid TEST_TTL_VAR value, using default',
          hash_including(env_var: 'TEST_TTL_VAR', default: default_value)
        )
        described_class.parse_ttl_env('TEST_TTL_VAR', default_value)
      end
    end

    context 'when environment variable is a float string' do
      before { ENV['TEST_TTL_VAR'] = '604800.5' }

      it 'returns the default value (strict integer parsing)' do
        result = described_class.parse_ttl_env('TEST_TTL_VAR', default_value)
        expect(result).to eq(default_value)
      end
    end

    context 'when environment variable is negative' do
      before { ENV['TEST_TTL_VAR'] = '-100' }

      it 'clamps to zero (lower bound)' do
        result = described_class.parse_ttl_env('TEST_TTL_VAR', default_value)
        expect(result).to eq(0)
      end
    end

    context 'when environment variable is zero' do
      before { ENV['TEST_TTL_VAR'] = '0' }

      it 'returns zero' do
        result = described_class.parse_ttl_env('TEST_TTL_VAR', default_value)
        expect(result).to eq(0)
      end
    end

    context 'when environment variable is hexadecimal' do
      before { ENV['TEST_TTL_VAR'] = '0x1234' }

      it 'returns the default value (base 10 only rejects hex)' do
        result = described_class.parse_ttl_env('TEST_TTL_VAR', default_value)
        expect(result).to eq(default_value)
      end
    end

    context 'when environment variable has leading zero' do
      before { ENV['TEST_TTL_VAR'] = '0777' }

      it 'parses as base 10 (leading zero ignored)' do
        # Integer('0777', 10) parses as 777 in base 10, not octal
        result = described_class.parse_ttl_env('TEST_TTL_VAR', default_value)
        expect(result).to eq(777)
      end
    end
  end

  describe '.free_tier_limits' do
    before do
      # Reset memoization before each test
      described_class.reset_free_tier_limits!
    end

    after do
      ENV.delete('PLAN_TTL_ANONYMOUS')
      described_class.reset_free_tier_limits!
    end

    context 'when PLAN_TTL_ANONYMOUS is not set' do
      it 'returns default secret_lifetime.max of 14 days (matches free_v1 plan)' do
        # See #3111: the constant must match `free_v1.limits.secret_lifetime`
        # in etc/billing.yaml (1_209_600) so that empty-planid orgs get the
        # same 14-day ceiling as the canonical free_v1 plan.
        limits = described_class.free_tier_limits
        expect(limits['secret_lifetime.max']).to eq(1_209_600)
        expect(limits['secret_lifetime.max']).to eq(14 * 24 * 60 * 60)
      end

      it 'returns default organization limits' do
        limits = described_class.free_tier_limits
        expect(limits['organizations.max']).to eq(5)
        expect(limits['teams.max']).to eq(0)
        expect(limits['members_per_team.max']).to eq(0)
      end
    end

    context 'when PLAN_TTL_ANONYMOUS is set to 30 days' do
      before { ENV['PLAN_TTL_ANONYMOUS'] = '2592000' }

      it 'returns overridden secret_lifetime.max' do
        limits = described_class.free_tier_limits
        expect(limits['secret_lifetime.max']).to eq(2_592_000)
      end

      it 'does not affect other limits' do
        limits = described_class.free_tier_limits
        expect(limits['organizations.max']).to eq(5)
        expect(limits['teams.max']).to eq(0)
      end
    end

    context 'when PLAN_TTL_ANONYMOUS exceeds MAX_TTL' do
      before { ENV['PLAN_TTL_ANONYMOUS'] = '999999999' }

      it 'caps secret_lifetime.max at MAX_TTL' do
        limits = described_class.free_tier_limits
        expect(limits['secret_lifetime.max']).to eq(described_class::MAX_TTL)
      end
    end

    context 'when PLAN_TTL_ANONYMOUS is invalid' do
      before { ENV['PLAN_TTL_ANONYMOUS'] = 'invalid' }

      it 'falls back to DEFAULT_FREE_TTL (14 days)' do
        limits = described_class.free_tier_limits
        expect(limits['secret_lifetime.max']).to eq(described_class::DEFAULT_FREE_TTL)
        expect(limits['secret_lifetime.max']).to eq(1_209_600)
      end
    end

    context 'memoization behavior' do
      it 'returns the same frozen hash on subsequent calls' do
        first_call = described_class.free_tier_limits
        second_call = described_class.free_tier_limits
        expect(first_call).to be(second_call)
        expect(first_call).to be_frozen
      end

      it 'can be reset for testing' do
        ENV['PLAN_TTL_ANONYMOUS'] = '1000'
        first_limits = described_class.free_tier_limits
        expect(first_limits['secret_lifetime.max']).to eq(1000)

        ENV['PLAN_TTL_ANONYMOUS'] = '2000'
        # Without reset, should return memoized value
        expect(described_class.free_tier_limits['secret_lifetime.max']).to eq(1000)

        # After reset, should pick up new value
        described_class.reset_free_tier_limits!
        expect(described_class.free_tier_limits['secret_lifetime.max']).to eq(2000)
      end
    end
  end

  describe 'FREE_TIER_LIMITS constant' do
    it 'is frozen' do
      expect(described_class::FREE_TIER_LIMITS).to be_frozen
    end

    it 'contains expected keys' do
      expect(described_class::FREE_TIER_LIMITS.keys).to include(
        'organizations.max',
        'teams.max',
        'members_per_team.max',
        'secret_lifetime.max'
      )
    end
  end

  describe 'MAX_TTL constant' do
    it 'equals 365 days in seconds' do
      expect(described_class::MAX_TTL).to eq(365 * 24 * 60 * 60)
      expect(described_class::MAX_TTL).to eq(31_536_000)
    end
  end

  describe 'DEFAULT_FREE_TTL constant' do
    it 'equals 14 days in seconds (matches free_v1 plan)' do
      # Regression test for #3111. The constant must match
      # `free_v1.limits.secret_lifetime` in etc/billing.yaml so that the
      # FREE_TIER_LIMITS fallback (used when planid is empty or cache miss)
      # does not silently impose a stricter ceiling than the canonical
      # free_v1 plan documented in the catalog.
      expect(described_class::DEFAULT_FREE_TTL).to eq(14 * 24 * 60 * 60)
      expect(described_class::DEFAULT_FREE_TTL).to eq(1_209_600)
    end

    it 'is positive' do
      expect(described_class::DEFAULT_FREE_TTL).to be > 0
    end

    it 'is less than MAX_TTL (365 days)' do
      expect(described_class::DEFAULT_FREE_TTL).to be < described_class::MAX_TTL
    end

    it 'is not the legacy 7-day value (regression guard for #3111)' do
      # If this assertion ever fails, someone has reverted DEFAULT_FREE_TTL
      # back to 604_800. That value drifts from `free_v1` in etc/billing.yaml
      # and silently caps free-tier users at 7 days instead of 14.
      expect(described_class::DEFAULT_FREE_TTL).not_to eq(604_800)
    end

    it 'matches the secret_lifetime declared by free_v1 in billing.example.yaml' do
      # The example billing YAML is the documentation source-of-truth for
      # the free tier ceiling. If this drifts, FREE_TIER_LIMITS will silently
      # disagree with what operators read in the catalog file.
      yaml_path = File.expand_path('../../../../../etc/examples/billing.example.yaml', __dir__)
      raw = File.read(yaml_path)
      processed = ERB.new(raw).result
      config = YAML.safe_load(processed, aliases: true)
      free_v1_lifetime = config.dig('plans', 'free_v1', 'limits', 'secret_lifetime')

      expect(free_v1_lifetime).to be_a(Integer)
      expect(described_class::DEFAULT_FREE_TTL).to eq(free_v1_lifetime)
    end
  end

  describe 'integration with limit_for' do
    # Mock class that includes WithEntitlements
    let(:test_class) do
      Class.new do
        include Onetime::Models::Features::WithEntitlements

        attr_accessor :planid

        def initialize(planid = nil)
          @planid = planid
        end

        def billing_enabled?
          true
        end
      end
    end

    let(:org) { test_class.new(nil) } # No plan = free tier

    before do
      described_class.reset_free_tier_limits!
    end

    after do
      ENV.delete('PLAN_TTL_ANONYMOUS')
      described_class.reset_free_tier_limits!
    end

    context 'when PLAN_TTL_ANONYMOUS is not set' do
      it 'limit_for returns default 14 days for secret_lifetime (#3111)' do
        expect(org.limit_for('secret_lifetime')).to eq(1_209_600)
        expect(org.limit_for('secret_lifetime')).to eq(described_class::DEFAULT_FREE_TTL)
      end

      it 'limit_for does NOT return the legacy 7-day cap' do
        # Customer-annoyance regression test: a billing-enabled empty-planid
        # org must not get the buggy 7-day cap from before #3111.
        expect(org.limit_for('secret_lifetime')).not_to eq(604_800)
      end
    end

    context 'when PLAN_TTL_ANONYMOUS is set to 30 days' do
      before { ENV['PLAN_TTL_ANONYMOUS'] = '2592000' }

      it 'limit_for returns overridden value' do
        expect(org.limit_for('secret_lifetime')).to eq(2_592_000)
      end
    end

    context 'when PLAN_TTL_ANONYMOUS is negative' do
      before { ENV['PLAN_TTL_ANONYMOUS'] = '-500' }

      it 'limit_for clamps to zero' do
        expect(org.limit_for('secret_lifetime')).to eq(0)
      end
    end

    context 'when PLAN_TTL_ANONYMOUS explicitly downgrades to legacy 7 days' do
      # Operators who want the old 7-day cap can still opt in via env var.
      # This protects deployments that intentionally relied on the legacy
      # constant value before #3111 was filed.
      before { ENV['PLAN_TTL_ANONYMOUS'] = '604800' }

      it 'limit_for honors the operator override' do
        expect(org.limit_for('secret_lifetime')).to eq(604_800)
      end
    end

    context 'when PLAN_TTL_ANONYMOUS matches the new default exactly' do
      before { ENV['PLAN_TTL_ANONYMOUS'] = '1209600' }

      it 'limit_for returns 14 days (idempotent override)' do
        expect(org.limit_for('secret_lifetime')).to eq(1_209_600)
        expect(org.limit_for('secret_lifetime')).to eq(described_class::DEFAULT_FREE_TTL)
      end
    end

    context 'symbol vs string resource keys (#3111 edge case)' do
      # The limit_for path flattens both symbol and string resource names
      # to "secret_lifetime.max". Both forms must agree for callers like
      # BaseSecretAction (string) and colonel test mode (symbol).
      it 'returns 14 days for the string form' do
        expect(org.limit_for('secret_lifetime')).to eq(1_209_600)
      end

      it 'returns 14 days for the symbol form' do
        expect(org.limit_for(:secret_lifetime)).to eq(1_209_600)
      end

      it 'returns the same value regardless of key form' do
        expect(org.limit_for(:secret_lifetime)).to eq(org.limit_for('secret_lifetime'))
      end
    end
  end

  # Regression suite for #3111: DEFAULT_FREE_TTL drifted from the canonical
  # `free_v1` plan in etc/billing.yaml, so a billing-enabled org with no
  # planid (or a cache-miss planid) was getting a stricter 7-day ceiling
  # than the published free_v1 14-day limit. These tests pin down the
  # contract so the drift cannot silently return.
  describe '#3111 regression: free tier TTL parity with free_v1' do
    let(:test_class) do
      Class.new do
        include Onetime::Models::Features::WithEntitlements

        attr_accessor :planid

        def initialize(planid = nil)
          @planid = planid
        end

        def billing_enabled?
          true
        end
      end
    end

    before do
      described_class.reset_free_tier_limits!
    end

    after do
      ENV.delete('PLAN_TTL_ANONYMOUS')
      described_class.reset_free_tier_limits!
    end

    context 'when planid is empty string (billing enabled, no plan assigned)' do
      let(:org) { test_class.new('') }

      it 'limit_for returns 14 days, not the legacy 7 days' do
        expect(org.limit_for('secret_lifetime')).to eq(1_209_600)
      end
    end

    context 'when planid is nil (billing enabled, unset)' do
      let(:org) { test_class.new(nil) }

      it 'limit_for returns 14 days, not the legacy 7 days' do
        expect(org.limit_for('secret_lifetime')).to eq(1_209_600)
      end
    end

    context 'when planid points to a missing plan (cache miss fallback)' do
      let(:org) { test_class.new('definitely_not_a_real_plan_id') }

      it 'limit_for returns 14 days via FREE_TIER_LIMITS fallback' do
        # When the plan cache misses, limit_for falls through to
        # free_tier_limit_for. With #3111 fixed, that fallback yields 14
        # days, matching the canonical free_v1 plan rather than the
        # legacy 7-day constant.
        allow(OT).to receive(:lw) # suppress expected fallback warning
        expect(org.limit_for('secret_lifetime')).to eq(1_209_600)
      end
    end

    context 'FREE_TIER_LIMITS constant (resolved at load time)' do
      it 'secret_lifetime.max equals 14 days' do
        # The legacy constant is captured from free_tier_limits at class
        # load. The class loaded before this spec ran, so we re-resolve
        # to confirm the current state matches DEFAULT_FREE_TTL.
        described_class.reset_free_tier_limits!
        ENV.delete('PLAN_TTL_ANONYMOUS')
        limits = described_class.free_tier_limits
        expect(limits['secret_lifetime.max']).to eq(described_class::DEFAULT_FREE_TTL)
        expect(limits['secret_lifetime.max']).to eq(1_209_600)
      end
    end

    describe 'boundary semantics around the 14-day ceiling' do
      let(:org) { test_class.new(nil) }

      it 'returns exactly 1_209_600 at the boundary' do
        expect(org.limit_for('secret_lifetime')).to eq(1_209_600)
      end

      it 'is strictly greater than the old 7-day value (no off-by-one)' do
        expect(org.limit_for('secret_lifetime')).to be > 604_800
      end

      it 'is exactly twice the old 7-day value' do
        # Documents the intent: free_v1 is "2 weeks" — twice 1 week.
        expect(org.limit_for('secret_lifetime')).to eq(2 * 604_800)
      end
    end
  end
end
