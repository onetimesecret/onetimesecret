# spec/unit/billing/operations/apply_subscription_to_org_spec.rb
#
# frozen_string_literal: true

# Test cases for ApplySubscriptionToOrg.apply_free_tier
#
# Centralizes cancel path for subscription deletions. Ensures:
# - Owner mode clears Stripe IDs and period end
# - Federated mode preserves Stripe IDs (owned by different org)
# - Both modes set canceled status, free plan, and clear complimentary
# - Entitlements are materialized from free_v1 plan
#
# Run: pnpm run test:rspec spec/unit/billing/operations/apply_subscription_to_org_spec.rb

require 'spec_helper'

require_relative '../../../../apps/web/billing/metadata'
require_relative '../../../../apps/web/billing/models/plan'
require_relative '../../../../apps/web/billing/operations/apply_subscription_to_org'

RSpec.describe 'Billing::Operations::ApplySubscriptionToOrg.apply_free_tier', billing: true do
  let(:operation) { Billing::Operations::ApplySubscriptionToOrg }

  # Mock materialized_entitlements set for size call in logging
  let(:materialized_entitlements_mock) do
    double('materialized_entitlements', size: 6)
  end

  # Mock rematerialize result for membership cascade
  let(:rematerialize_result) do
    { success: 2, failed: 0, total: 2, failed_ids: [] }
  end

  # Org double with writable attributes and materialization support
  let(:org) do
    instance_double(
      Onetime::Organization,
      'subscription_status=' => nil,
      'planid=' => nil,
      'complimentary=' => nil,
      'subscription_period_end=' => nil,
      'stripe_subscription_id=' => nil,
      extid: 'on_test123',
      materialize_entitlements_from_config: true,
      materialized_entitlements: materialized_entitlements_mock,
      rematerialize_all_memberships!: rematerialize_result
    )
  end

  describe 'owner mode (owner: true)' do
    it 'sets subscription_status to canceled' do
      allow(org).to receive(:save).and_return(true)
      expect(org).to receive(:subscription_status=).with('canceled')

      operation.apply_free_tier(org, owner: true)
    end

    it 'sets planid to FREE_PLAN_ID' do
      allow(org).to receive(:save).and_return(true)
      expect(org).to receive(:planid=).with(Billing::Metadata::FREE_PLAN_ID)

      operation.apply_free_tier(org, owner: true)
    end

    it 'clears complimentary' do
      allow(org).to receive(:save).and_return(true)
      expect(org).to receive(:complimentary=).with(nil)

      operation.apply_free_tier(org, owner: true)
    end

    it 'clears subscription_period_end' do
      allow(org).to receive(:save).and_return(true)
      expect(org).to receive(:subscription_period_end=).with(nil)

      operation.apply_free_tier(org, owner: true)
    end

    it 'clears stripe_subscription_id' do
      allow(org).to receive(:save).and_return(true)
      expect(org).to receive(:stripe_subscription_id=).with(nil)

      operation.apply_free_tier(org, owner: true)
    end

    it 'calls org.save when save: true (default)' do
      expect(org).to receive(:save).and_return(true)

      result = operation.apply_free_tier(org, owner: true)
      expect(result).to be true
    end
  end

  describe 'federated mode (owner: false)' do
    it 'sets subscription_status to canceled' do
      allow(org).to receive(:save).and_return(true)
      expect(org).to receive(:subscription_status=).with('canceled')

      operation.apply_free_tier(org, owner: false)
    end

    it 'sets planid to FREE_PLAN_ID' do
      allow(org).to receive(:save).and_return(true)
      expect(org).to receive(:planid=).with(Billing::Metadata::FREE_PLAN_ID)

      operation.apply_free_tier(org, owner: false)
    end

    it 'clears complimentary' do
      allow(org).to receive(:save).and_return(true)
      expect(org).to receive(:complimentary=).with(nil)

      operation.apply_free_tier(org, owner: false)
    end

    it 'does NOT clear subscription_period_end' do
      allow(org).to receive(:save).and_return(true)
      expect(org).not_to receive(:subscription_period_end=)

      operation.apply_free_tier(org, owner: false)
    end

    it 'does NOT clear stripe_subscription_id' do
      allow(org).to receive(:save).and_return(true)
      expect(org).not_to receive(:stripe_subscription_id=)

      operation.apply_free_tier(org, owner: false)
    end
  end

  describe 'save behavior' do
    it 'calls org.save when save: true' do
      expect(org).to receive(:save).and_return(true)

      result = operation.apply_free_tier(org, owner: true, save: true)
      expect(result).to be true
    end

    it 'does NOT call org.save when save: false' do
      expect(org).not_to receive(:save)

      result = operation.apply_free_tier(org, owner: true, save: false)
      expect(result).to be_nil
    end

    it 'returns nil when save: false' do
      result = operation.apply_free_tier(org, owner: true, save: false)
      expect(result).to be_nil
    end

    it 'returns org.save result when save: true' do
      allow(org).to receive(:save).and_return(false)

      result = operation.apply_free_tier(org, owner: true, save: true)
      expect(result).to be false
    end
  end

  describe 'membership cascade failure logging' do
    before { allow(org).to receive(:save).and_return(true) }

    context 'when the cascade reports failures' do
      let(:rematerialize_result) { { success: 0, failed: 1, total: 1, failed_ids: ['mem_z'] } }

      it 'escalates to OT.le with FREE_PLAN_ID, counts, and failed ids' do
        expect(OT).to receive(:le).with(
          '[ApplySubscriptionToOrg] membership re-materialization had failures (free tier)',
          hash_including(
            org_extid: 'on_test123',
            planid: Billing::Metadata::FREE_PLAN_ID,
            memberships_total: 1,
            memberships_failed: 1,
            memberships_failed_ids: ['mem_z'],
          ),
        )

        operation.apply_free_tier(org, owner: true)
      end
    end

    context 'when the cascade reports no failures' do
      it 'does NOT escalate to OT.le' do
        expect(OT).not_to receive(:le)

        operation.apply_free_tier(org, owner: true)
      end
    end
  end
end
