# spec/unit/models/features/with_entitlements_test_mode_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Unit tests for WithEntitlements Test Mode
#
# Tests the Thread.current[:entitlement_test_planid] override mechanism
# that allows colonels to test features from different plan tiers.
#
# NOTE: Tests the Thread.current override mechanism for Issue #2244.
#
RSpec.describe 'WithEntitlements Test Mode', billing: true do
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

  after do
    # Clear Thread.current after each test to prevent pollution
    Thread.current[:entitlement_test_planid] = nil
  end

  describe '#entitlements with test mode' do
    context 'when no test override is set' do
      it 'returns actual plan entitlements' do
        expect(org.entitlements).to match_array(%w[create_secrets basic_sharing])
      end

      it 'does not include higher tier entitlements' do
        expect(org.entitlements).not_to include('custom_domains')
        expect(org.entitlements).not_to include('api_access')
      end
    end

    context 'when test planid is set in Thread.current' do
      it 'overrides to identity_v1 entitlements' do
        Thread.current[:entitlement_test_planid] = 'identity_v1'

        expect(org.entitlements).to include('custom_domains')
        expect(org.entitlements).to include('create_team')
        expect(org.entitlements).to include('priority_support')
      end

      it 'overrides to multi_team_v1 entitlements' do
        Thread.current[:entitlement_test_planid] = 'multi_team_v1'

        expect(org.entitlements).to include('api_access')
        expect(org.entitlements).to include('audit_logs')
        expect(org.entitlements).to include('advanced_analytics')
      end

      it 'overrides even for higher tier actual plans' do
        # Organization with identity_v1 can test as free
        higher_tier_org = test_class.new('identity_v1')
        Thread.current[:entitlement_test_planid] = 'free'

        expect(higher_tier_org.entitlements).to match_array(%w[create_secrets basic_sharing])
        expect(higher_tier_org.entitlements).not_to include('custom_domains')
      end
    end

    context 'when test planid is invalid' do
      it 'returns empty array for non-existent plan' do
        Thread.current[:entitlement_test_planid] = 'nonexistent_plan'

        expect(org.entitlements).to eq([])
      end

      it 'returns empty array for nil planid' do
        Thread.current[:entitlement_test_planid] = nil

        # Falls back to actual plan
        expect(org.entitlements).to match_array(%w[create_secrets basic_sharing])
      end

      it 'returns empty array for empty string planid' do
        Thread.current[:entitlement_test_planid] = ''

        # Falls back to actual plan
        expect(org.entitlements).to match_array(%w[create_secrets basic_sharing])
      end
    end

    context 'thread isolation' do
      it 'override is isolated to current thread' do
        Thread.current[:entitlement_test_planid] = 'identity_v1'

        # Create new thread without override
        other_thread_entitlements = nil
        thread = Thread.new do
          # Should use actual plan, not override from parent thread
          other_thread_entitlements = org.entitlements
        end
        thread.join

        # Main thread sees override
        expect(org.entitlements).to include('custom_domains')

        # Other thread sees actual plan
        expect(other_thread_entitlements).to match_array(%w[create_secrets basic_sharing])
        expect(other_thread_entitlements).not_to include('custom_domains')
      end

      it 'different threads can have different overrides' do
        Thread.current[:entitlement_test_planid] = 'free'
        main_entitlements = org.entitlements

        thread_entitlements = nil
        thread = Thread.new do
          Thread.current[:entitlement_test_planid] = 'multi_team_v1'
          thread_entitlements = org.entitlements
        end
        thread.join

        # Main thread: free
        expect(main_entitlements).to match_array(%w[create_secrets basic_sharing])

        # Other thread: multi_team_v1
        expect(thread_entitlements).to include('api_access')
        expect(thread_entitlements).to include('audit_logs')
      end
    end
  end

  describe '#can? with test mode' do
    context 'when no test override is set' do
      it 'checks against actual plan entitlements' do
        expect(org.can?('create_secrets')).to be true
        expect(org.can?('custom_domains')).to be false
      end
    end

    context 'when test planid is set' do
      it 'checks against test plan entitlements' do
        Thread.current[:entitlement_test_planid] = 'identity_v1'

        expect(org.can?('custom_domains')).to be true
        expect(org.can?('create_team')).to be true
        expect(org.can?('api_access')).to be false
      end

      it 'handles symbol entitlement names' do
        Thread.current[:entitlement_test_planid] = 'multi_team_v1'

        expect(org.can?(:api_access)).to be true
        expect(org.can?(:audit_logs)).to be true
      end
    end

    context 'downgrade testing' do
      it 'allows testing lower tier from higher tier plan' do
        premium_org = test_class.new('multi_team_v1')

        # Verify actual entitlements
        expect(premium_org.can?('api_access')).to be true

        # Test as free tier
        Thread.current[:entitlement_test_planid] = 'free'

        expect(premium_org.can?('api_access')).to be false
        expect(premium_org.can?('create_secrets')).to be true
      end
    end
  end

  describe '#limit_for with test mode' do
    context 'when no test override is set' do
      it 'returns actual plan limits' do
        expect(org.limit_for('teams')).to eq(0)
      end
    end

    context 'when test planid is set' do
      it 'returns test plan limits' do
        Thread.current[:entitlement_test_planid] = 'identity_v1'

        expect(org.limit_for('teams')).to eq(1)
      end

      it 'returns unlimited for multi_team plan' do
        Thread.current[:entitlement_test_planid] = 'multi_team_v1'

        expect(org.limit_for('teams')).to eq(Float::INFINITY)
      end
    end
  end

  describe '#check_entitlement with test mode' do
    before do
      # Stub Billing::PlanHelpers for these tests
      stub_const('Billing::PlanHelpers', Class.new do
        def self.upgrade_path_for(entitlement, current_plan)
          # Simple upgrade path logic for tests
          return 'identity_v1' if current_plan == 'free'
          return 'multi_team_v1' if current_plan == 'identity_v1'
          nil
        end
      end)
    end

    context 'when no test override is set' do
      it 'returns actual plan check result' do
        result = org.check_entitlement('custom_domains')

        expect(result[:allowed]).to be false
        expect(result[:current_plan]).to eq('free')
        expect(result[:upgrade_needed]).to be true
      end
    end

    context 'when test planid is set' do
      it 'returns test plan check result' do
        Thread.current[:entitlement_test_planid] = 'identity_v1'

        result = org.check_entitlement('custom_domains')

        expect(result[:allowed]).to be true
        expect(result[:current_plan]).to eq('free') # Still shows actual plan
        expect(result[:upgrade_needed]).to be false
      end

      it 'shows upgrade needed for entitlement not in test plan' do
        Thread.current[:entitlement_test_planid] = 'identity_v1'

        result = org.check_entitlement('api_access')

        expect(result[:allowed]).to be false
        expect(result[:upgrade_needed]).to be true
      end
    end
  end

  describe '#at_limit? with test mode' do
    context 'when no test override is set' do
      it 'checks against actual plan limits' do
        expect(org.at_limit?('teams', 0)).to be true
        expect(org.at_limit?('teams', 1)).to be true
      end
    end

    context 'when test planid is set' do
      it 'checks against test plan limits' do
        Thread.current[:entitlement_test_planid] = 'identity_v1'

        expect(org.at_limit?('teams', 0)).to be false
        expect(org.at_limit?('teams', 1)).to be true
        expect(org.at_limit?('teams', 2)).to be true
      end

      it 'never at limit for unlimited plans' do
        Thread.current[:entitlement_test_planid] = 'multi_team_v1'

        expect(org.at_limit?('teams', 999)).to be false
      end
    end
  end

  describe 'clearing test override' do
    it 'reverts to actual plan when set to nil' do
      Thread.current[:entitlement_test_planid] = 'multi_team_v1'
      expect(org.can?('api_access')).to be true

      Thread.current[:entitlement_test_planid] = nil
      expect(org.can?('api_access')).to be false
    end

    it 'reverts to actual plan when set to empty string' do
      Thread.current[:entitlement_test_planid] = 'identity_v1'
      expect(org.can?('custom_domains')).to be true

      Thread.current[:entitlement_test_planid] = ''
      expect(org.can?('custom_domains')).to be false
    end
  end

  describe 'edge cases' do
    context 'organization without planid' do
      let(:no_plan_org) { test_class.new(nil) }

      it 'returns empty array for actual plan' do
        expect(no_plan_org.entitlements).to eq([])
      end

      it 'returns test plan entitlements when override set' do
        Thread.current[:entitlement_test_planid] = 'identity_v1'

        expect(no_plan_org.entitlements).to include('custom_domains')
      end
    end

    context 'organization with empty planid' do
      let(:empty_plan_org) { test_class.new('') }

      it 'returns empty array for actual plan' do
        expect(empty_plan_org.entitlements).to eq([])
      end

      it 'returns test plan entitlements when override set' do
        Thread.current[:entitlement_test_planid] = 'multi_team_v1'

        expect(empty_plan_org.entitlements).to include('api_access')
      end
    end

    context 'rapid override changes' do
      it 'handles rapid switching between plans' do
        # Free
        expect(org.can?('api_access')).to be false

        # Identity
        Thread.current[:entitlement_test_planid] = 'identity_v1'
        expect(org.can?('custom_domains')).to be true
        expect(org.can?('api_access')).to be false

        # Multi-team
        Thread.current[:entitlement_test_planid] = 'multi_team_v1'
        expect(org.can?('api_access')).to be true

        # Back to free
        Thread.current[:entitlement_test_planid] = 'free'
        expect(org.can?('custom_domains')).to be false
        expect(org.can?('api_access')).to be false

        # Clear override
        Thread.current[:entitlement_test_planid] = nil
        expect(org.can?('create_secrets')).to be true
      end
    end
  end
end
