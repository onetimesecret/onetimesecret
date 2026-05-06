# spec/unit/onetime/models/features/with_entitlements_can_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Unit tests for WithEntitlements#can? predicate, focused on
# `extended_default_expiration` because it gates TTLs above
# DEFAULT_FREE_TTL in BaseSecretAction#process_ttl on every API
# version (#3074).
#
# These tests pin down the predicate semantics independent of the
# downstream gate so a change to either side is caught here first.
#
RSpec.describe 'WithEntitlements#can? for extended_default_expiration', billing: true do
  let(:test_class) do
    Class.new do
      include Onetime::Models::Features::WithEntitlements

      attr_accessor :planid

      def initialize(planid)
        @planid = planid
      end

      def billing_enabled?
        true
      end
    end
  end

  before do
    BillingTestHelpers.populate_test_plans([
      {
        plan_id: 'free_no_extended',
        name: 'Free (no extended)',
        tier: 1,
        interval: 'month',
        region: 'us',
        entitlements: %w[create_secrets api_access],
        limits: { 'secret_lifetime.max' => '604800' }, # 7 days
      },
      {
        plan_id: 'paid_with_extended',
        name: 'Paid (with extended)',
        tier: 2,
        interval: 'month',
        region: 'us',
        entitlements: %w[create_secrets api_access extended_default_expiration],
        limits: { 'secret_lifetime.max' => '2592000' }, # 30 days
      },
    ])
  end

  context 'when plan lacks extended_default_expiration' do
    let(:org) { test_class.new('free_no_extended') }

    it 'returns false for can?(:extended_default_expiration)' do
      expect(org.can?(:extended_default_expiration)).to be(false)
    end

    it 'returns false for the string form' do
      expect(org.can?('extended_default_expiration')).to be(false)
    end
  end

  context 'when plan has extended_default_expiration' do
    let(:org) { test_class.new('paid_with_extended') }

    it 'returns true for can?(:extended_default_expiration)' do
      expect(org.can?(:extended_default_expiration)).to be(true)
    end

    it 'returns true for the string form' do
      expect(org.can?('extended_default_expiration')).to be(true)
    end
  end

  context 'when planid is unknown (cache miss falls back to FREE_TIER_ENTITLEMENTS)' do
    let(:org) { test_class.new('unknown_plan_id') }

    it 'returns false because the free fallback omits the entitlement' do
      expect(org.can?('extended_default_expiration')).to be(false)
    end
  end

  describe 'FREE_TIER_ENTITLEMENTS constant' do
    it 'does NOT include extended_default_expiration' do
      # The fallback returned on plan cache miss for billing-enabled deployments.
      # Including this entitlement here would silently grant 30-day TTLs to any
      # mis-configured plan and defeat the gate's purpose.
      expect(
        Onetime::Models::Features::WithEntitlements::FREE_TIER_ENTITLEMENTS,
      ).not_to include('extended_default_expiration')
    end
  end

  describe 'STANDALONE_ENTITLEMENTS constant' do
    it 'DOES include extended_default_expiration' do
      # Standalone/self-hosted (billing disabled) gets full access; the gate
      # must not impede self-hosted users.
      expect(
        Onetime::Models::Features::WithEntitlements::STANDALONE_ENTITLEMENTS,
      ).to include('extended_default_expiration')
    end
  end
end
