# spec/unit/onetime/models/features/with_entitlements_cache_miss_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../apps/web/billing/errors'

# Tests for fail-closed behavior when plan cache miss occurs.
# Issue #3089: Plan ID Matching Overhaul
#
# Prior behavior: Silent fallback to FREE_TIER_ENTITLEMENTS
# New behavior: Raises Billing::PlanCacheMissError
#
RSpec.describe 'WithEntitlements cache miss behavior', billing: true do
  let(:test_class) do
    Class.new do
      include Onetime::Models::Features::WithEntitlements
      include Onetime::Models::Features::WithMaterializedLimits
      include Onetime::Models::Features::WithPlanEntitlements

      attr_accessor :planid, :extid

      def initialize(planid, extid: 'test_org_abc123')
        @planid = planid
        @extid = extid
      end

      def billing_enabled?
        true
      end
    end
  end

  describe '#entitlements' do
    context 'when planid is not in cache or config' do
      let(:org) { test_class.new('nonexistent_plan_xyz') }

      it 'raises PlanCacheMissError (fail-closed)' do
        expect { org.entitlements }
          .to raise_error(Billing::PlanCacheMissError) { |error|
            expect(error.plan_id).to eq('nonexistent_plan_xyz')
            expect(error.context).to eq('WithPlanEntitlements#entitlements')
            expect(error.organization_id).to eq('test_org_abc123')
          }
      end
    end

    context 'when planid is empty (no plan assigned)' do
      let(:org) { test_class.new('') }

      it 'returns FREE_TIER_ENTITLEMENTS (not an error)' do
        expect(org.entitlements).to eq(
          Onetime::Models::Features::WithPlanEntitlements::FREE_TIER_ENTITLEMENTS
        )
      end
    end

    context 'when planid is nil' do
      let(:org) { test_class.new(nil) }

      it 'returns FREE_TIER_ENTITLEMENTS (not an error)' do
        expect(org.entitlements).to eq(
          Onetime::Models::Features::WithPlanEntitlements::FREE_TIER_ENTITLEMENTS
        )
      end
    end

    context 'when billing is disabled' do
      let(:org) do
        obj = test_class.new('any_plan')
        allow(obj).to receive(:billing_enabled?).and_return(false)
        obj
      end

      it 'returns STANDALONE_ENTITLEMENTS (fail-open for self-hosted)' do
        expect(org.entitlements).to eq(
          Onetime::Models::Features::WithPlanEntitlements::STANDALONE_ENTITLEMENTS
        )
      end
    end

    context 'when plan exists in config (billing.yaml fallback)' do
      let(:org) { test_class.new('free_v1') }

      it 'returns config-defined entitlements without raising' do
        expect { org.entitlements }.not_to raise_error
      end
    end
  end

  describe '#limit_for' do
    context 'when planid is not in cache or config' do
      let(:org) { test_class.new('nonexistent_plan_xyz') }

      it 'raises PlanCacheMissError (fail-closed)' do
        expect { org.limit_for('teams') }
          .to raise_error(Billing::PlanCacheMissError) { |error|
            expect(error.plan_id).to eq('nonexistent_plan_xyz')
            expect(error.context).to eq('WithMaterializedLimits#limit_for')
            expect(error.resource).to eq('teams.max')
            expect(error.organization_id).to eq('test_org_abc123')
          }
      end
    end

    context 'when planid is empty' do
      let(:org) { test_class.new('') }

      it 'returns free tier limit (not an error)' do
        result = org.limit_for('teams')
        expect(result).to be_a(Numeric)
      end
    end

    context 'when billing is disabled' do
      let(:org) do
        obj = test_class.new('any_plan')
        allow(obj).to receive(:billing_enabled?).and_return(false)
        obj
      end

      it 'returns Float::INFINITY (unlimited for self-hosted)' do
        expect(org.limit_for('teams')).to eq(Float::INFINITY)
      end
    end
  end
end

RSpec.describe 'Organization default planid', billing: true do
  describe 'Organization#init' do
    it 'defaults to free_v1 (not bare free)' do
      org = Onetime::Organization.new(objid: 'test_org_123')
      expect(org.planid).to eq('free_v1')
    end
  end
end
