# spec/unit/onetime/models/features/with_materialized_entitlements_spec.rb
#
# frozen_string_literal: true

# Unit tests for WithMaterializedEntitlements feature module (Issue #3134)
#
# Covers:
#  1. Reconciler (apply_entitlements): plan + grants - revokes
#  2. Materialization from plan / from config hash
#  3. Staleness detection (entitlements_stale? / entitlements_materialized?)
#  4. Operator overrides (grant_entitlement / revoke_entitlement)
#  5. Content hash determinism
#
# Tests in categories 1–4 that operate on Familia sets require Redis (port 2121).
# Category 5 (entitlements_content_hash) and staleness parsing are pure-Ruby and
# run without Redis.
#
# Run: pnpm run test:rspec spec/unit/onetime/models/features/with_materialized_entitlements_spec.rb

require 'spec_helper'

require_relative '../../../../../lib/onetime/models/organization/features/with_materialized_entitlements'
require_relative '../../../../../lib/onetime/models/organization/features/with_materialized_limits'

RSpec.describe 'WithMaterializedEntitlements', billing: true do

  # ---------------------------------------------------------------------------
  # Test double: a minimal class that includes the feature and supplies the
  # Familia set/hashkey/field doubles needed for Redis-touching tests.
  # For pure-Ruby tests (Section 5) we use ClassMethods directly.
  # ---------------------------------------------------------------------------

  # Lightweight in-memory set that mirrors the Familia set interface used by
  # the reconciler (add / delete / each / clear / to_a / size).
  class FakeSet
    def initialize = @data = Set.new
    def add(v)    = @data.add(v.to_s)
    def delete(v) = @data.delete(v.to_s)
    alias remove_element delete
    def each(&b)  = @data.each(&b)
    def clear     = @data.clear
    def to_a      = @data.to_a
    def size      = @data.size
    def include?(v) = @data.include?(v.to_s)
  end

  # Minimal hashkey (just [] and []= forwarding to a Hash)
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

  # ClassMethods module that holds entitlements_content_hash
  let(:class_methods_mod) { Onetime::Models::Features::WithMaterializedEntitlements::ClassMethods }

  let(:test_class) do
    cm = class_methods_mod

    Class.new do
      # Pull in InstanceMethods and ClassMethods (mirrors what base.include/extend does)
      include Onetime::Models::Features::WithMaterializedEntitlements::InstanceMethods
      include Onetime::Models::Features::WithMaterializedLimits::InstanceMethods
      extend cm

      attr_accessor :materialized_entitlements_at

      def initialize
        @entitlements_plan         = FakeSet.new
        @limits_plan               = FakeHashKey.new
        @entitlements_grants       = FakeSet.new
        @entitlements_revokes      = FakeSet.new
        @materialized_entitlements = FakeSet.new
        @materialized_entitlements_at = nil
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

  # ClassMethods are extended onto test_class, so call them as test_class.method_name
  # feature_mod is an alias so examples read clearly
  let(:feature_mod) { test_class }

  # ---------------------------------------------------------------------------
  # Helpers — build plan-like doubles
  # ---------------------------------------------------------------------------

  def plan_with(entitlements:, limits: {})
    plan_ents = FakeSet.new
    entitlements.each { |e| plan_ents.add(e) }

    plan_lims = FakeHashKey.new
    limits.each { |k, v| plan_lims[k] = v.to_s }

    instance_double(
      Billing::Plan,
      entitlements: plan_ents,
      limits: plan_lims,
    )
  end

  # ============================================================================
  # Section 1: Reconciler — apply_entitlements
  # ============================================================================

  describe '#apply_entitlements' do
    it 'plan only → materialized equals plan' do
      org.entitlements_plan.add('api_access')
      org.entitlements_plan.add('custom_domains')

      result = org.apply_entitlements

      expect(result).to contain_exactly('api_access', 'custom_domains')
      expect(org.materialized_entitlements.to_a).to contain_exactly('api_access', 'custom_domains')
    end

    it 'plan + grants → union of both' do
      org.entitlements_plan.add('api_access')
      org.entitlements_grants.add('manage_teams')

      org.apply_entitlements

      expect(org.materialized_entitlements.to_a).to contain_exactly('api_access', 'manage_teams')
    end

    it 'plan - revokes → plan minus revoked item' do
      org.entitlements_plan.add('api_access')
      org.entitlements_plan.add('custom_domains')
      org.entitlements_revokes.add('custom_domains')

      org.apply_entitlements

      expect(org.materialized_entitlements.to_a).to contain_exactly('api_access')
    end

    it 'plan + grants - revokes in correct order' do
      org.entitlements_plan.add('api_access')
      org.entitlements_grants.add('manage_teams')
      org.entitlements_revokes.add('api_access')

      org.apply_entitlements

      # api_access in plan but revoked; manage_teams added via grant
      expect(org.materialized_entitlements.to_a).to contain_exactly('manage_teams')
    end

    it 'revoking a grant does not leave it in materialized' do
      org.entitlements_grants.add('manage_teams')
      org.entitlements_revokes.add('manage_teams')

      org.apply_entitlements

      expect(org.materialized_entitlements.to_a).not_to include('manage_teams')
    end

    it 'empty plan + grants → only grants materialized' do
      org.entitlements_grants.add('api_access')

      org.apply_entitlements

      expect(org.materialized_entitlements.to_a).to contain_exactly('api_access')
    end

    it 'all plan entitlements revoked → empty materialized set' do
      org.entitlements_plan.add('api_access')
      org.entitlements_revokes.add('api_access')

      org.apply_entitlements

      expect(org.materialized_entitlements.to_a).to be_empty
    end

    it 'idempotent: calling twice produces the same result' do
      org.entitlements_plan.add('api_access')
      org.entitlements_grants.add('manage_teams')
      org.entitlements_revokes.add('api_access')

      org.apply_entitlements
      first_result = org.materialized_entitlements.to_a.sort

      org.apply_entitlements
      second_result = org.materialized_entitlements.to_a.sort

      expect(second_result).to eq(first_result)
    end
  end

  # ============================================================================
  # Section 2: Materialization from plan / from config
  # ============================================================================

  describe '#materialize_entitlements_from_plan' do
    let(:plan) do
      plan_with(
        entitlements: %w[api_access custom_domains manage_teams],
        limits: { 'teams.max' => '5', 'secret_lifetime.max' => 'unlimited' },
      )
    end

    it 'copies plan entitlements to entitlements_plan' do
      org.materialize_entitlements_from_plan(plan)

      expect(org.entitlements_plan.to_a).to contain_exactly('api_access', 'custom_domains', 'manage_teams')
    end

    it 'copies plan limits to limits_plan' do
      org.materialize_entitlements_from_plan(plan)

      expect(org.limits_plan['teams.max']).to eq('5')
      expect(org.limits_plan['secret_lifetime.max']).to eq('unlimited')
    end

    it 'runs reconciliation (materialized_entitlements is populated)' do
      org.materialize_entitlements_from_plan(plan)

      expect(org.materialized_entitlements.to_a).to contain_exactly('api_access', 'custom_domains', 'manage_teams')
    end

    it 'stamps materialized_entitlements_at with timestamp:hash format' do
      org.materialize_entitlements_from_plan(plan)

      stamp = org.materialized_entitlements_at.to_s
      expect(stamp).to match(/\A\d+:[0-9a-f]{12}\z/)
    end

    it 'returns true on success' do
      expect(org.materialize_entitlements_from_plan(plan)).to be true
    end

    it 'replaces previous entitlements_plan on re-materialization' do
      org.entitlements_plan.add('stale_entitlement')

      org.materialize_entitlements_from_plan(plan)

      expect(org.entitlements_plan.to_a).not_to include('stale_entitlement')
    end

    it 'replaces previous limits_plan on re-materialization' do
      org.limits_plan['old_key'] = 'old_value'

      org.materialize_entitlements_from_plan(plan)

      expect(org.limits_plan['old_key']).to be_nil
    end
  end

  describe '#materialize_entitlements_from_config' do
    let(:config_data) do
      {
        entitlements: %w[create_secrets view_receipt api_access],
        limits: { 'secret_lifetime.max' => '1209600', 'organizations.max' => '5' },
      }
    end

    it 'copies config entitlements to entitlements_plan' do
      org.materialize_entitlements_from_config(config_data)

      expect(org.entitlements_plan.to_a).to contain_exactly('create_secrets', 'view_receipt', 'api_access')
    end

    it 'copies config limits to limits_plan as strings' do
      org.materialize_entitlements_from_config(config_data)

      expect(org.limits_plan['secret_lifetime.max']).to eq('1209600')
      expect(org.limits_plan['organizations.max']).to eq('5')
    end

    it 'populates materialized_entitlements' do
      org.materialize_entitlements_from_config(config_data)

      expect(org.materialized_entitlements.to_a).to contain_exactly('create_secrets', 'view_receipt', 'api_access')
    end

    it 'stamps materialized_entitlements_at' do
      org.materialize_entitlements_from_config(config_data)

      stamp = org.materialized_entitlements_at.to_s
      expect(stamp).to match(/\A\d+:[0-9a-f]{12}\z/)
    end

    it 'returns true on success' do
      expect(org.materialize_entitlements_from_config(config_data)).to be true
    end

    it 'handles missing :entitlements key gracefully' do
      org.materialize_entitlements_from_config({ limits: {} })

      expect(org.materialized_entitlements.to_a).to be_empty
    end

    it 'handles missing :limits key gracefully' do
      org.materialize_entitlements_from_config({ entitlements: ['api_access'] })

      expect(org.limits_plan['anything']).to be_nil
    end
  end

  # ============================================================================
  # Section 3: Staleness detection
  # ============================================================================

  describe '#entitlements_materialized?' do
    it 'returns false when materialized_entitlements_at is nil' do
      org.materialized_entitlements_at = nil

      expect(org.entitlements_materialized?).to be false
    end

    it 'returns false when materialized_entitlements_at is empty string' do
      org.materialized_entitlements_at = ''

      expect(org.entitlements_materialized?).to be false
    end

    it 'returns true when materialized_entitlements_at is set' do
      org.materialized_entitlements_at = '1716000000:abc123def456'

      expect(org.entitlements_materialized?).to be true
    end
  end

  describe '#materialized_entitlements_at_parsed' do
    it 'returns nil when not set' do
      org.materialized_entitlements_at = nil

      expect(org.materialized_entitlements_at_parsed).to be_nil
    end

    it 'parses timestamp and content_hash from stamp' do
      org.materialized_entitlements_at = '1716000000:abc123def456'
      result = org.materialized_entitlements_at_parsed

      expect(result[:timestamp]).to eq(1716000000)
      expect(result[:content_hash]).to eq('abc123def456')
    end

    it 'returns nil for malformed stamp (no colon)' do
      org.materialized_entitlements_at = 'badstamp'

      expect(org.materialized_entitlements_at_parsed).to be_nil
    end
  end

  describe '#entitlements_stale?' do
    let(:plan_ents) { %w[api_access custom_domains] }
    let(:plan) { plan_with(entitlements: plan_ents) }

    it 'returns true when not yet materialized' do
      org.materialized_entitlements_at = nil

      expect(org.entitlements_stale?(plan)).to be true
    end

    it 'returns false when hash matches current plan' do
      expected_hash = feature_mod.entitlements_content_hash(plan_ents)
      org.materialized_entitlements_at = "1716000000:#{expected_hash}"

      expect(org.entitlements_stale?(plan)).to be false
    end

    it 'returns true when plan entitlements changed since last materialization' do
      old_hash = feature_mod.entitlements_content_hash(%w[api_access])
      org.materialized_entitlements_at = "1716000000:#{old_hash}"

      # plan now has different entitlements
      expect(org.entitlements_stale?(plan)).to be true
    end

    it 'returns true when only plan limits changed (entitlements identical)' do
      # Regression for #3280: a plan edit that only touches limits used to look
      # "fresh" because the stamp hashed entitlements only.
      old_limits = { 'teams.max' => '1' }
      old_hash   = feature_mod.snapshot_content_hash(plan_ents, old_limits)
      org.materialized_entitlements_at = "1716000000:#{old_hash}"

      new_plan = plan_with(entitlements: plan_ents, limits: { 'teams.max' => '5' })

      expect(org.entitlements_stale?(new_plan)).to be true
    end

    it 'returns false when both entitlements and limits match plan' do
      limits        = { 'teams.max' => '5', 'secret_lifetime.max' => 'unlimited' }
      expected_hash = feature_mod.snapshot_content_hash(plan_ents, limits)
      org.materialized_entitlements_at = "1716000000:#{expected_hash}"

      stamped_plan = plan_with(entitlements: plan_ents, limits: limits)

      expect(org.entitlements_stale?(stamped_plan)).to be false
    end

    it 'accepts a config-hash plan and compares against its limits' do
      limits        = { 'organizations.max' => '5' }
      expected_hash = feature_mod.snapshot_content_hash(plan_ents, limits)
      org.materialized_entitlements_at = "1716000000:#{expected_hash}"

      config_plan = { entitlements: plan_ents, limits: limits }

      expect(org.entitlements_stale?(config_plan)).to be false

      changed_config = { entitlements: plan_ents, limits: { 'organizations.max' => '10' } }
      expect(org.entitlements_stale?(changed_config)).to be true
    end
  end

  # ============================================================================
  # Section 4: Operator overrides — grant_entitlement / revoke_entitlement
  # ============================================================================

  describe '#grant_entitlement' do
    before { org.entitlements_plan.add('api_access') }

    it 'adds to grants set' do
      org.grant_entitlement('manage_teams')

      expect(org.entitlements_grants.include?('manage_teams')).to be true
    end

    it 'removes the entitlement from revokes if it was there' do
      org.entitlements_revokes.add('manage_teams')
      org.grant_entitlement('manage_teams')

      expect(org.entitlements_revokes.include?('manage_teams')).to be false
    end

    it 'appears in materialized_entitlements after reconciliation' do
      org.grant_entitlement('manage_teams')

      expect(org.materialized_entitlements.include?('manage_teams')).to be true
    end

    it 'accepts symbol and coerces to string' do
      org.grant_entitlement(:manage_teams)

      expect(org.entitlements_grants.include?('manage_teams')).to be true
    end
  end

  describe '#revoke_entitlement' do
    before do
      org.entitlements_plan.add('api_access')
      org.entitlements_plan.add('custom_domains')
      org.apply_entitlements
    end

    it 'adds to revokes set' do
      org.revoke_entitlement('custom_domains')

      expect(org.entitlements_revokes.include?('custom_domains')).to be true
    end

    it 'removes the entitlement from grants if it was there' do
      org.entitlements_grants.add('custom_domains')
      org.revoke_entitlement('custom_domains')

      expect(org.entitlements_grants.include?('custom_domains')).to be false
    end

    it 'removes the entitlement from materialized_entitlements' do
      org.revoke_entitlement('custom_domains')

      expect(org.materialized_entitlements.include?('custom_domains')).to be false
    end

    it 'accepts symbol and coerces to string' do
      org.revoke_entitlement(:custom_domains)

      expect(org.entitlements_revokes.include?('custom_domains')).to be true
    end
  end

  describe '#clear_entitlement_overrides' do
    before do
      org.entitlements_plan.add('api_access')
      org.entitlements_grants.add('manage_teams')
      org.entitlements_revokes.add('api_access')
      org.apply_entitlements
    end

    it 'clears grants set' do
      org.clear_entitlement_overrides

      expect(org.entitlements_grants.to_a).to be_empty
    end

    it 'clears revokes set' do
      org.clear_entitlement_overrides

      expect(org.entitlements_revokes.to_a).to be_empty
    end

    it 'returns plan-only entitlements after clearing' do
      result = org.clear_entitlement_overrides

      expect(result).to contain_exactly('api_access')
      expect(org.materialized_entitlements.to_a).to contain_exactly('api_access')
    end
  end

  # ============================================================================
  # Section 5: Limits — materialized_limit_for
  # ============================================================================

  describe '#materialized_limit_for' do
    before do
      org.limits_plan['teams.max']          = '5'
      org.limits_plan['secret_lifetime.max'] = 'unlimited'
    end

    it 'returns integer for numeric limit' do
      expect(org.materialized_limit_for('teams.max')).to eq(5)
    end

    it 'returns Float::INFINITY for "unlimited"' do
      expect(org.materialized_limit_for('secret_lifetime.max')).to eq(Float::INFINITY)
    end

    it 'returns 0 for unknown key' do
      expect(org.materialized_limit_for('unknown_resource.max')).to eq(0)
    end
  end

  # ============================================================================
  # Section 6: Content hash determinism (ClassMethods — pure Ruby, no Redis)
  # ============================================================================

  describe '.entitlements_content_hash' do
    subject { feature_mod }

    it 'produces the same hash regardless of input order' do
      h1 = subject.entitlements_content_hash(%w[api_access custom_domains manage_teams])
      h2 = subject.entitlements_content_hash(%w[manage_teams api_access custom_domains])

      expect(h1).to eq(h2)
    end

    it 'produces different hashes for different entitlement sets' do
      h1 = subject.entitlements_content_hash(%w[api_access])
      h2 = subject.entitlements_content_hash(%w[api_access custom_domains])

      expect(h1).not_to eq(h2)
    end

    it 'returns a 12-character hex string' do
      hash = subject.entitlements_content_hash(%w[api_access])

      expect(hash).to match(/\A[0-9a-f]{12}\z/)
    end

    it 'returns a stable hash for empty array' do
      h = subject.entitlements_content_hash([])

      expect(h).to be_a(String)
      expect(h.length).to eq(12)
    end
  end

  describe '.snapshot_content_hash' do
    subject { feature_mod }

    it 'equals entitlements_content_hash when limits are empty (back-compat)' do
      ents = %w[api_access custom_domains]

      expect(subject.snapshot_content_hash(ents, {})).to eq(subject.entitlements_content_hash(ents))
      expect(subject.snapshot_content_hash(ents, nil)).to eq(subject.entitlements_content_hash(ents))
    end

    it 'differs when limit values differ' do
      ents = %w[api_access]

      h1 = subject.snapshot_content_hash(ents, { 'teams.max' => '1' })
      h2 = subject.snapshot_content_hash(ents, { 'teams.max' => '5' })

      expect(h1).not_to eq(h2)
    end

    it 'is stable regardless of limit key order' do
      ents   = %w[api_access]
      limits = { 'teams.max' => '5', 'secret_lifetime.max' => 'unlimited' }

      h1 = subject.snapshot_content_hash(ents, limits)
      h2 = subject.snapshot_content_hash(ents, limits.to_a.reverse.to_h)

      expect(h1).to eq(h2)
    end

    it 'treats string and symbol limit keys as equivalent' do
      ents = %w[api_access]

      h1 = subject.snapshot_content_hash(ents, { 'teams.max' => '5' })
      h2 = subject.snapshot_content_hash(ents, { teams_max: '5' })

      # different keys -> different hashes, but stringification within a single
      # call must be deterministic
      expect(h2).to eq(subject.snapshot_content_hash(ents, { 'teams_max' => '5' }))
      expect(h1).not_to eq(h2)
    end
  end
end
