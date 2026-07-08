# spec/unit/onetime/models/features/with_entitlements_preview_mode_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'set' # FakeSet uses Set.new; not guaranteed to be required by load order

require_relative '../../../../../lib/onetime/models/organization/features/with_materialized_entitlements'

# Unit tests for the entitlement/limit preview chokepoints (ADR-020).
#
# Preview state lives in a request-scoped Fiber-local
# (Onetime::EntitlementPreview) populated by middleware; the chokepoints —
# WithEntitlements#entitlements, WithPlanEntitlements#entitlements and
# WithMaterializedLimits#limit_for — consult it so every consumer above them
# is preview-aware without a session parameter.
#
# Session grants/revokes sets are written to real Redis (port 2121) because
# the reconciler reads them via Familia.dbclient.
RSpec.describe 'WithEntitlements Preview Mode', billing: true do
  # Lightweight in-memory set mirroring the Familia set interface used by
  # the reconciler (same pattern as with_materialized_entitlements_spec.rb).
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

  # Mirrors Organization's feature mix minus Familia storage: the plan chain
  # (WithPlanEntitlements over WithEntitlements) plus limits, WITHOUT the
  # session reconciler. Hosts like this must fall through the preview guard.
  let(:plain_class) do
    Class.new do
      include Onetime::Models::Features::WithEntitlements
      include Onetime::Models::Features::WithMaterializedLimits
      include Onetime::Models::Features::WithPlanEntitlements

      attr_accessor :planid, :extid

      def initialize(planid, extid: 'test_org_preview_spec')
        @planid = planid
        @extid  = extid
      end

      def billing_enabled?
        true
      end
    end
  end

  # Adds the real reconciler (WithMaterializedEntitlements::InstanceMethods)
  # on top of the plan chain, backed by FakeSet storage — the same shape a
  # real Organization presents to the preview guard.
  let(:reconciling_class) do
    Class.new do
      include Onetime::Models::Features::WithEntitlements
      include Onetime::Models::Features::WithMaterializedLimits
      include Onetime::Models::Features::WithPlanEntitlements
      include Onetime::Models::Features::WithMaterializedEntitlements::InstanceMethods

      attr_accessor :planid, :extid, :materialized_entitlements_at

      def initialize(planid, extid: 'test_org_preview_reconciler')
        @planid                       = planid
        @extid                        = extid
        @entitlements_plan            = FakeSet.new
        @entitlements_grants          = FakeSet.new
        @entitlements_revokes         = FakeSet.new
        @materialized_entitlements    = FakeSet.new
        @materialized_entitlements_at = nil
      end

      def entitlements_plan         = @entitlements_plan
      def entitlements_grants       = @entitlements_grants
      def entitlements_revokes      = @entitlements_revokes
      def materialized_entitlements = @materialized_entitlements

      def billing_enabled?
        true
      end
    end
  end

  let(:free_entitlements)     { %w[create_secrets basic_sharing] }
  let(:identity_entitlements) { %w[create_secrets basic_sharing custom_domains create_team priority_support] }

  let(:org) { plain_class.new('free') }

  # Session-scoped override sets in real Redis, unique per example
  let(:session_suffix) { SecureRandom.hex(4) }
  let(:grants_key)     { "spec:preview:#{session_suffix}:grants" }
  let(:revokes_key)    { "spec:preview:#{session_suffix}:revokes" }

  def seed_preview_sets(grants:, revokes:)
    redis = Familia.dbclient
    redis.sadd(grants_key, grants) if grants.any?
    redis.sadd(revokes_key, revokes) if revokes.any?
  end

  after do
    Familia.dbclient.del(grants_key, revokes_key)
  end

  # Setup test plans in cache
  before do
    BillingTestHelpers.populate_test_plans([
      {
        plan_id: 'free',
        name: 'Free',
        tier: 1,
        interval: 'month',
        region: 'us',
        entitlements: %w[create_secrets basic_sharing],
        limits: { 'teams.max' => '0' },
      },
      {
        plan_id: 'identity_v1',
        name: 'Identity Plus',
        tier: 2,
        interval: 'month',
        region: 'us',
        entitlements: %w[create_secrets basic_sharing custom_domains create_team priority_support],
        limits: { 'teams.max' => '1' },
      },
      {
        plan_id: 'multi_team_v1',
        name: 'Multi-Team',
        tier: 3,
        interval: 'month',
        region: 'us',
        entitlements: %w[create_secrets basic_sharing custom_domains create_teams api_access audit_logs advanced_analytics],
        limits: { 'teams.max' => 'unlimited' },
      },
    ])
  end

  describe '#entitlements without a preview context' do
    it 'returns the actual plan entitlements' do
      expect(org.entitlements).to match_array(free_entitlements)
    end

    it 'returns materialized entitlements for a materialized org' do
      materialized = reconciling_class.new('free')
      free_entitlements.each { |e| materialized.materialized_entitlements.add(e) }
      materialized.materialized_entitlements_at = "#{Time.now.to_i}:abc123def456"

      expect(materialized.entitlements).to match_array(free_entitlements)
    end

    it 'does not include higher tier entitlements' do
      expect(org.entitlements).not_to include('custom_domains')
      expect(org.entitlements).not_to include('api_access')
    end
  end

  describe '#entitlements with an active preview (reconciler host)' do
    let(:materialized_org) do
      instance = reconciling_class.new('free')
      free_entitlements.each { |e| instance.materialized_entitlements.add(e) }
      instance.materialized_entitlements_at = "#{Time.now.to_i}:abc123def456"
      instance
    end

    before do
      # Reset-and-substitute: revoke the actual entitlements, grant the
      # preview plan's set
      seed_preview_sets(grants: identity_entitlements, revokes: free_entitlements)
    end

    it 'returns the reconciled preview entitlements' do
      with_entitlement_preview(planid: 'identity_v1', grants_key: grants_key, revokes_key: revokes_key) do
        expect(materialized_org.entitlements).to match_array(identity_entitlements)
      end
    end

    it 'reflects the override through can?' do
      with_entitlement_preview(planid: 'identity_v1', grants_key: grants_key, revokes_key: revokes_key) do
        expect(materialized_org.can?('custom_domains')).to be true
        expect(materialized_org.can?('create_team')).to be true
      end
    end

    it 'reverts to materialized entitlements once the context is cleared' do
      with_entitlement_preview(planid: 'identity_v1', grants_key: grants_key, revokes_key: revokes_key) do
        materialized_org.entitlements
      end

      expect(materialized_org.entitlements).to match_array(free_entitlements)
      expect(materialized_org.can?('custom_domains')).to be false
    end

    it 'ignores a planid-only context (no reconciliation keys)' do
      with_entitlement_preview(planid: 'identity_v1') do
        expect(materialized_org.entitlements).to match_array(free_entitlements)
      end
    end
  end

  describe '#entitlements with an active preview (non-materialized org)' do
    # The MRO regression this design exists to prevent: the Plan.load
    # fallback branches in WithPlanEntitlements#entitlements return without
    # reaching super, so a guard placed only in the base module would be
    # skipped for orgs that were never materialized.
    let(:unmaterialized_org) { reconciling_class.new('free') }

    before do
      seed_preview_sets(grants: identity_entitlements, revokes: free_entitlements)
    end

    it 'preview wins over the Plan.load fallback' do
      with_entitlement_preview(planid: 'identity_v1', grants_key: grants_key, revokes_key: revokes_key) do
        expect(unmaterialized_org.entitlements).to match_array(identity_entitlements)
      end
    end

    it 'preview wins over the empty-planid FREE tier fallback' do
      no_plan_org = reconciling_class.new('')

      with_entitlement_preview(planid: 'identity_v1', grants_key: grants_key, revokes_key: revokes_key) do
        expect(no_plan_org.entitlements).to match_array(identity_entitlements)
      end
    end

    it 'falls back to the Plan.load chain without a context' do
      expect(unmaterialized_org.entitlements).to match_array(free_entitlements)
    end
  end

  describe '#entitlements with an active preview (host without reconciler)' do
    it 'falls back cleanly to the actual entitlements' do
      with_entitlement_preview(planid: 'identity_v1', grants_key: grants_key, revokes_key: revokes_key) do
        expect(org.entitlements).to match_array(free_entitlements)
      end
    end

    it 'keeps can? on the actual entitlements' do
      with_entitlement_preview(planid: 'identity_v1', grants_key: grants_key, revokes_key: revokes_key) do
        expect(org.can?('custom_domains')).to be false
      end
    end
  end

  describe '#limit_for' do
    context 'without a preview context' do
      it 'returns the actual plan limit' do
        expect(org.limit_for('teams')).to eq(0)
      end
    end

    context 'with a preview context carrying a planid' do
      it 'returns the preview plan limit for identity_v1' do
        with_entitlement_preview(planid: 'identity_v1') do
          expect(org.limit_for('teams')).to eq(1)
        end
      end

      it 'returns unlimited for the multi_team plan' do
        with_entitlement_preview(planid: 'multi_team_v1') do
          expect(org.limit_for('teams')).to eq(Float::INFINITY)
        end
      end

      it 'returns 0 for a non-existent preview plan' do
        with_entitlement_preview(planid: 'nonexistent_plan') do
          expect(org.limit_for('teams')).to eq(0)
        end
      end

      it 'reverts to the actual plan limit once cleared' do
        with_entitlement_preview(planid: 'identity_v1') { org.limit_for('teams') }

        expect(org.limit_for('teams')).to eq(0)
      end
    end

    context 'with a preview context lacking a planid' do
      it 'falls back to the actual plan limit' do
        with_entitlement_preview(grants_key: grants_key, revokes_key: revokes_key) do
          expect(org.limit_for('teams')).to eq(0)
        end
      end
    end
  end

  describe '#at_limit?' do
    it 'checks against the actual plan limits without a context' do
      expect(org.at_limit?('teams', 0)).to be true
      expect(org.at_limit?('teams', 1)).to be true
    end

    it 'checks against the preview plan limits with a context' do
      with_entitlement_preview(planid: 'identity_v1') do
        expect(org.at_limit?('teams', 0)).to be false
        expect(org.at_limit?('teams', 1)).to be true
      end
    end
  end

  describe '#check_entitlement (without preview context)' do
    before do
      stub_const('Billing::PlanHelpers', Class.new do
        def self.upgrade_path_for(entitlement, current_plan)
          return 'identity_v1' if current_plan == 'free'
          return 'multi_team_v1' if current_plan == 'identity_v1'
          nil
        end
      end)
    end

    it 'returns actual plan check result' do
      result = org.check_entitlement('custom_domains')

      expect(result[:allowed]).to be false
      expect(result[:current_plan]).to eq('free')
      expect(result[:upgrade_needed]).to be true
    end

    it 'shows allowed for entitlements in plan' do
      result = org.check_entitlement('create_secrets')

      expect(result[:allowed]).to be true
      expect(result[:upgrade_needed]).to be false
    end
  end

  describe 'edge cases' do
    context 'organization without planid' do
      let(:no_plan_org) { plain_class.new(nil) }

      it 'returns FREE tier entitlements (graceful degradation)' do
        expect(no_plan_org.entitlements).to eq(
          Onetime::Models::Features::WithPlanEntitlements::FREE_TIER_ENTITLEMENTS
        )
      end
    end

    context 'organization with empty planid' do
      let(:empty_plan_org) { plain_class.new('') }

      it 'returns FREE tier entitlements (graceful degradation)' do
        expect(empty_plan_org.entitlements).to eq(
          Onetime::Models::Features::WithPlanEntitlements::FREE_TIER_ENTITLEMENTS
        )
      end
    end
  end
end
