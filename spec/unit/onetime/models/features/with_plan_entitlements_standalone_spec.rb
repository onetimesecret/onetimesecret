# spec/unit/onetime/models/features/with_plan_entitlements_standalone_spec.rb
#
# frozen_string_literal: true

# Unit tests for WithPlanEntitlements#materialize_standalone_entitlements!
# (Stage 2 Unit C, ADR-012 §Standalone mode).
#
# Covers:
#   1. Billing-disabled: writes STANDALONE_ENTITLEMENTS to materialized storage
#   2. Billing-enabled: no-op, returns false
#   3. Idempotency: callable repeatedly without changing the entitlement set
#
# These tests reuse the FakeSet/FakeHashKey scaffold from
# with_materialized_entitlements_spec.rb. The anonymous test class mixes in both
# WithMaterializedEntitlements and WithPlanEntitlements so `super` resolution
# in `entitlements` and the underlying `materialize_entitlements_from_config`
# reconciler are both reachable.
#
# Run: bundle exec rspec spec/unit/onetime/models/features/with_plan_entitlements_standalone_spec.rb

require 'spec_helper'

require_relative '../../../../../lib/onetime/models/organization/features/with_materialized_entitlements'
require_relative '../../../../../lib/onetime/models/organization/features/with_materialized_limits'
require_relative '../../../../../lib/onetime/models/organization/features/with_plan_entitlements'

RSpec.describe 'WithPlanEntitlements#materialize_standalone_entitlements!', billing: true do
  # In-memory Familia set substitute used by the reconciler.
  class FakeSet
    def initialize = @data = Set.new
    def add(v) = @data.add(v.to_s)
    def delete(v) = @data.delete(v.to_s)
    alias remove_element delete
    def each(&b) = @data.each(&b)
    def clear = @data.clear
    def to_a = @data.to_a
    def size = @data.size
    def include?(v) = @data.include?(v.to_s)
  end

  class FakeHashKey
    def initialize
      @data = {}
    end

    def [](k)
      @data[k.to_s]
    end

    def []=(k, v)
      @data[k.to_s] = v.to_s
    end

    def hgetall
      @data.dup
    end

    def clear
      @data.clear
    end
  end

  let(:billing_state) { false }

  let(:test_class) do
    bs = -> { billing_state }

    Class.new do
      include Onetime::Models::Features::WithMaterializedEntitlements::InstanceMethods
      include Onetime::Models::Features::WithMaterializedLimits::InstanceMethods
      include Onetime::Models::Features::WithPlanEntitlements::InstanceMethods
      extend Onetime::Models::Features::WithMaterializedEntitlements::ClassMethods

      attr_accessor :materialized_entitlements_at, :planid, :extid

      define_method(:billing_enabled?) { bs.call }

      def initialize
        @entitlements_plan            = FakeSet.new
        @limits_plan                  = FakeHashKey.new
        @entitlements_grants          = FakeSet.new
        @entitlements_revokes         = FakeSet.new
        @materialized_entitlements    = FakeSet.new
        @materialized_entitlements_at = nil
        @planid                       = ''
        @extid                        = 'test_org_standalone'
      end

      def entitlements_plan         = @entitlements_plan
      def limits_plan               = @limits_plan
      def entitlements_grants       = @entitlements_grants
      def entitlements_revokes      = @entitlements_revokes
      def materialized_entitlements = @materialized_entitlements

      # Stub for Familia::Horreum#save_with_collections
      def save_with_collections(update_expiration: true)
        yield if block_given?
        true
      end

      # Stub for Familia::Horreum#transaction (MULTI/EXEC wrapper)
      def transaction
        yield if block_given?
      end
    end
  end

  let(:org) { test_class.new }
  let(:standalone_constant) do
    Onetime::Models::Features::WithPlanEntitlements::STANDALONE_ENTITLEMENTS
  end

  # ============================================================================
  # Standalone mode (billing disabled): happy path
  # ============================================================================

  describe 'when billing is disabled (standalone)' do
    let(:billing_state) { false }

    it 'returns a truthy value (delegates to materialize_entitlements_from_config)' do
      expect(org.materialize_standalone_entitlements!).to be_truthy
    end

    it 'writes STANDALONE_ENTITLEMENTS into materialized_entitlements' do
      org.materialize_standalone_entitlements!

      expect(org.materialized_entitlements.to_a.sort).to eq(standalone_constant.sort)
    end

    it 'writes STANDALONE_ENTITLEMENTS into entitlements_plan' do
      org.materialize_standalone_entitlements!

      expect(org.entitlements_plan.to_a.sort).to eq(standalone_constant.sort)
    end

    it 'leaves limits_plan empty (standalone passes an empty limits hash)' do
      org.materialize_standalone_entitlements!

      expect(org.limits_plan.hgetall).to eq({})
    end

    it 'stamps materialized_entitlements_at in timestamp:hash form' do
      org.materialize_standalone_entitlements!

      expect(org.materialized_entitlements_at.to_s).to match(/\A\d+:[0-9a-f]{12}\z/)
    end

    it 'marks the org as materialized (entitlements_materialized? -> true)' do
      org.materialize_standalone_entitlements!

      expect(org.entitlements_materialized?).to be true
    end
  end

  # ============================================================================
  # Billing-enabled mode: no-op
  # ============================================================================

  describe 'when billing is enabled' do
    let(:billing_state) { true }

    it 'returns false without materializing' do
      expect(org.materialize_standalone_entitlements!).to be false
    end

    it 'does not populate materialized_entitlements' do
      org.materialize_standalone_entitlements!

      expect(org.materialized_entitlements.to_a).to be_empty
    end

    it 'does not populate entitlements_plan' do
      org.materialize_standalone_entitlements!

      expect(org.entitlements_plan.to_a).to be_empty
    end

    it 'does not stamp materialized_entitlements_at' do
      org.materialize_standalone_entitlements!

      expect(org.materialized_entitlements_at).to be_nil
    end

    it 'entitlements_materialized? stays false' do
      org.materialize_standalone_entitlements!

      expect(org.entitlements_materialized?).to be false
    end
  end

  # ============================================================================
  # Idempotency: repeated calls produce the same effective state
  # ============================================================================

  describe 'idempotency (standalone mode)' do
    let(:billing_state) { false }

    it 'second call returns a truthy value (not false — false is reserved for billing branch)' do
      org.materialize_standalone_entitlements!
      expect(org.materialize_standalone_entitlements!).to be_truthy
    end

    it 'materialized_entitlements is unchanged after a second call' do
      org.materialize_standalone_entitlements!
      first = org.materialized_entitlements.to_a.sort

      org.materialize_standalone_entitlements!
      second = org.materialized_entitlements.to_a.sort

      expect(second).to eq(first)
    end

    it 'entitlements_plan is unchanged after a second call' do
      org.materialize_standalone_entitlements!
      first = org.entitlements_plan.to_a.sort

      org.materialize_standalone_entitlements!
      second = org.entitlements_plan.to_a.sort

      expect(second).to eq(first)
    end

    it 'content_hash portion of materialized_entitlements_at is stable across calls' do
      # STANDALONE_ENTITLEMENTS is a frozen constant, so the content_hash must
      # be deterministic. Only the timestamp portion may differ.
      org.materialize_standalone_entitlements!
      first_hash = org.materialized_entitlements_at.split(':').last

      org.materialize_standalone_entitlements!
      second_hash = org.materialized_entitlements_at.split(':').last

      expect(second_hash).to eq(first_hash)
    end

    it 'materialized_entitlements_at refreshes each call (timestamp may advance)' do
      # The method re-runs reconciliation every time; the stamp is rewritten.
      # We don't assert on monotonic progression because Familia.now resolution
      # may collapse within the same second — we only assert it is set and
      # well-formed after the second call.
      org.materialize_standalone_entitlements!
      org.materialize_standalone_entitlements!

      expect(org.materialized_entitlements_at.to_s).to match(/\A\d+:[0-9a-f]{12}\z/)
    end
  end
end
