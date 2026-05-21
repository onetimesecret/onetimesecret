# spec/unit/onetime/models/features/with_entitlements_preview_mode_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Unit tests for WithEntitlements Preview Mode
#
# Tests the session-based preview mode mechanism that allows colonels
# to test features from different plan tiers.
#
# The preview mode uses explicit session parameters instead of Thread.current,
# making it safer for async contexts and easier to test.
#
RSpec.describe 'WithEntitlements Preview Mode', billing: true do
  # Mock class that includes WithEntitlements
  let(:test_class) do
    Class.new do
      include Onetime::Models::Features::WithEntitlements

      attr_accessor :planid

      def initialize(planid)
        @planid = planid
      end

      # Mock billing_enabled? to return true for tests
      def billing_enabled?
        true
      end
    end
  end

  let(:org) { test_class.new('free') }

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

  describe '#entitlements_for_request' do
    context 'when session is nil' do
      it 'returns actual plan entitlements' do
        expect(org.entitlements_for_request(nil)).to match_array(%w[create_secrets basic_sharing])
      end
    end

    context 'when session has no preview keys' do
      let(:session) { {} }

      it 'returns actual plan entitlements' do
        expect(org.entitlements_for_request(session)).to match_array(%w[create_secrets basic_sharing])
      end

      it 'does not include higher tier entitlements' do
        entitlements = org.entitlements_for_request(session)
        expect(entitlements).not_to include('custom_domains')
        expect(entitlements).not_to include('api_access')
      end
    end

    context 'when session has preview keys but org lacks reconciler' do
      let(:session) do
        {
          entitlement_preview_grants_key: 'session:abc:grants',
          entitlement_preview_revokes_key: 'session:abc:revokes',
        }
      end

      it 'falls back to actual entitlements when reconciler not available' do
        # Mock org without reconciler (respond_to? returns false)
        expect(org.entitlements_for_request(session)).to match_array(%w[create_secrets basic_sharing])
      end
    end
  end

  describe '#limit_for_request' do
    context 'when session is nil' do
      it 'returns actual plan limits' do
        expect(org.limit_for_request('teams', nil)).to eq(0)
      end
    end

    context 'when session has no preview planid' do
      let(:session) { {} }

      it 'returns actual plan limits' do
        expect(org.limit_for_request('teams', session)).to eq(0)
      end
    end

    context 'when session has preview planid' do
      it 'returns preview plan limits for identity_v1' do
        session = { entitlement_preview_planid: 'identity_v1' }
        expect(org.limit_for_request('teams', session)).to eq(1)
      end

      it 'returns unlimited for multi_team plan' do
        session = { entitlement_preview_planid: 'multi_team_v1' }
        expect(org.limit_for_request('teams', session)).to eq(Float::INFINITY)
      end

      it 'ignores empty preview planid' do
        session = { entitlement_preview_planid: '' }
        expect(org.limit_for_request('teams', session)).to eq(0) # falls back to actual
      end

      it 'ignores nil preview planid' do
        session = { entitlement_preview_planid: nil }
        expect(org.limit_for_request('teams', session)).to eq(0) # falls back to actual
      end
    end
  end

  describe '#entitlements (without session context)' do
    it 'returns actual plan entitlements' do
      expect(org.entitlements).to match_array(%w[create_secrets basic_sharing])
    end

    it 'is not affected by any external state' do
      # No Thread.current pollution
      expect(org.entitlements).to match_array(%w[create_secrets basic_sharing])
    end
  end

  describe '#can? (without session context)' do
    it 'checks against actual plan entitlements' do
      expect(org.can?('create_secrets')).to be true
      expect(org.can?('custom_domains')).to be false
    end

    it 'handles symbol entitlement names' do
      expect(org.can?(:create_secrets)).to be true
      expect(org.can?(:api_access)).to be false
    end
  end

  describe '#limit_for (without session context)' do
    it 'returns actual plan limits' do
      expect(org.limit_for('teams')).to eq(0)
    end
  end

  describe '#check_entitlement (without session context)' do
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

  describe '#at_limit? (without session context)' do
    it 'checks against actual plan limits' do
      expect(org.at_limit?('teams', 0)).to be true
      expect(org.at_limit?('teams', 1)).to be true
    end
  end

  describe 'edge cases' do
    context 'organization without planid' do
      let(:no_plan_org) { test_class.new(nil) }

      it 'returns FREE tier entitlements (graceful degradation)' do
        expect(no_plan_org.entitlements).to eq(
          Onetime::Models::Features::WithEntitlements::FREE_TIER_ENTITLEMENTS
        )
      end

      it 'returns FREE tier entitlements via entitlements_for_request' do
        expect(no_plan_org.entitlements_for_request(nil)).to eq(
          Onetime::Models::Features::WithEntitlements::FREE_TIER_ENTITLEMENTS
        )
      end
    end

    context 'organization with empty planid' do
      let(:empty_plan_org) { test_class.new('') }

      it 'returns FREE tier entitlements (graceful degradation)' do
        expect(empty_plan_org.entitlements).to eq(
          Onetime::Models::Features::WithEntitlements::FREE_TIER_ENTITLEMENTS
        )
      end
    end

    context 'invalid preview planid in session' do
      it 'returns 0 for non-existent plan limit' do
        session = { entitlement_preview_planid: 'nonexistent_plan' }
        expect(org.limit_for_request('teams', session)).to eq(0)
      end
    end
  end

  describe 'session parameter handling' do
    it 'accepts hash-like objects for session' do
      # Rack session is hash-like
      session = { entitlement_preview_planid: 'identity_v1' }
      expect(org.limit_for_request('teams', session)).to eq(1)
    end

    it 'safely handles session with string keys' do
      # Some contexts may use string keys
      session = { 'entitlement_preview_planid' => 'identity_v1' }
      # Should not crash, falls back to actual
      expect(org.limit_for_request('teams', session)).to eq(0)
    end

    it 'safely handles non-hash session' do
      # Edge case: corrupted session
      expect(org.entitlements_for_request('not a hash')).to match_array(%w[create_secrets basic_sharing])
    end
  end
end
