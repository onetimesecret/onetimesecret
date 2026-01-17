# spec/unit/onetime/models/features/with_entitlements_ttl_env_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Unit tests for WithEntitlements TTL Environment Variable Support
#
# Tests the parse_ttl_env method and free_tier_limits dynamic computation
# that allows Docker/self-hosted deployments to override TTL limits via
# environment variables.
#
# This provides upgrade continuity with PR #2393 from main branch.
# @see https://github.com/onetimesecret/onetimesecret/issues/2390
#
RSpec.describe Onetime::Models::Features::WithEntitlements do
  describe '.parse_ttl_env' do
    let(:default_value) { 604_800 } # 7 days

    after do
      # Clean up environment after each test
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

      it 'logs a warning' do
        expect(OT).to receive(:lw).with(
          /Invalid TEST_TTL_VAR value '123abc'/,
          anything
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

      it 'returns the negative value (allows negative for potential special cases)' do
        result = described_class.parse_ttl_env('TEST_TTL_VAR', default_value)
        expect(result).to eq(-100)
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

      it 'returns the default value (base 10 only)' do
        # Integer() with explicit base 10 rejects hex
        result = described_class.parse_ttl_env('TEST_TTL_VAR', default_value)
        expect(result).to eq(default_value)
      end
    end

    context 'when environment variable is octal' do
      before { ENV['TEST_TTL_VAR'] = '0777' }

      it 'returns the default value (base 10 only)' do
        # Integer() with explicit base 10 rejects octal prefix
        result = described_class.parse_ttl_env('TEST_TTL_VAR', default_value)
        expect(result).to eq(default_value)
      end
    end
  end

  describe '.free_tier_limits' do
    after do
      ENV.delete('PLAN_TTL_ANONYMOUS')
    end

    context 'when PLAN_TTL_ANONYMOUS is not set' do
      it 'returns default secret_lifetime.max of 7 days' do
        limits = described_class.free_tier_limits
        expect(limits['secret_lifetime.max']).to eq(604_800)
      end

      it 'returns default organization limits' do
        limits = described_class.free_tier_limits
        expect(limits['organizations.max']).to eq(5)
        expect(limits['teams.max']).to eq(0)
        expect(limits['members_per_team.max']).to eq(0)
      end
    end

    context 'when PLAN_TTL_ANONYMOUS is set to 30 days' do
      before { ENV['PLAN_TTL_ANONYMOUS'] = '2592000' } # 30 days

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

      it 'falls back to default value' do
        limits = described_class.free_tier_limits
        expect(limits['secret_lifetime.max']).to eq(604_800)
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
    it 'equals 7 days in seconds' do
      expect(described_class::DEFAULT_FREE_TTL).to eq(7 * 24 * 60 * 60)
      expect(described_class::DEFAULT_FREE_TTL).to eq(604_800)
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

    after do
      ENV.delete('PLAN_TTL_ANONYMOUS')
    end

    context 'when PLAN_TTL_ANONYMOUS is not set' do
      it 'limit_for returns default 7 days for secret_lifetime' do
        expect(org.limit_for('secret_lifetime')).to eq(604_800)
      end
    end

    context 'when PLAN_TTL_ANONYMOUS is set to 30 days' do
      before { ENV['PLAN_TTL_ANONYMOUS'] = '2592000' }

      it 'limit_for returns overridden value' do
        expect(org.limit_for('secret_lifetime')).to eq(2_592_000)
      end
    end
  end
end
