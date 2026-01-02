# spec/integration/all/entitlement_test_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Load the ColonelAPI application and its dependencies
# apps/api is in the load path from spec_helper
require 'colonel/application'

# Integration tests for Colonel Entitlement Test Mode API
#
# Tests the /api/colonel/entitlement-test endpoint that allows colonels
# to override their organization's plan entitlements for testing purposes.
#
# Requires:
# - Full OT boot (for apps/api/colonel)
# - Billing enabled with test plans
# - Session middleware
# - Organization with colonel customer
#
RSpec.describe 'ColonelAPI::Logic::Colonel::SetEntitlementTest', type: :integration, billing: true do
  include Rack::Test::Methods

  let(:app) do
    ColonelAPI::Application.new
  end

  let(:colonel_customer) do
    # Create a mock colonel customer
    double(
      'Customer',
      custid: 'colonel@example.com',
      role: 'colonel',
      colonel?: true,
      extid: SecureRandom.uuid,
    )
  end

  let(:organization) do
    # Create a mock organization
    double(
      'Organization',
      planid: 'free',
      objid: 'org_123',
    )
  end

  let(:session_data) { {} }

  let(:params) { {} }

  # Helper to create logic instance
  # Usage: create_logic(planid: 'identity_v1')
  #        create_logic(planid: 'identity_v1', customer: some_customer)
  #        create_logic(planid: 'identity_v1', org: some_org)
  def create_logic(planid: nil, customer: nil, org: nil)
    customer ||= colonel_customer
    org ||= organization

    # Build params hash from the planid (use string keys to match Rack params)
    params_hash = { 'planid' => planid }

    # Mock session object
    session = double('Session')
    allow(session).to receive(:[]).with(:entitlement_test_planid) { session_data[:entitlement_test_planid] }
    allow(session).to receive(:[]=) do |key, value|
      session_data[key] = value
    end
    allow(session).to receive(:delete) do |key|
      session_data.delete(key)
    end

    # Create strategy_result mock (this is what Logic::Base#initialize expects)
    strategy_result = double('StrategyResult')
    allow(strategy_result).to receive(:session).and_return(session)
    allow(strategy_result).to receive(:user).and_return(customer)
    allow(strategy_result).to receive(:metadata).and_return({ organization: org })

    # Create logic instance with proper arguments
    logic = ColonelAPI::Logic::Colonel::SetEntitlementTest.new(
      strategy_result,
      params_hash,
    )

    # Mock organization method if org provided
    allow(logic).to receive(:organization).and_return(org)

    # Mock verify_one_of_roles! method
    allow(logic).to receive(:verify_one_of_roles!) do |roles|
      raise OT::Unauthorized unless roles[:colonel] && customer.colonel?
    end

    logic
  end

  # Setup test plans in Redis cache
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
    # Clear session data after each test
    session_data.clear
  end

  describe 'POST /api/colonel/entitlement-test' do
    context 'setting test mode' do
      it 'sets test planid in session' do
        logic = create_logic(planid: 'identity_v1')

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(session_data[:entitlement_test_planid]).to eq('identity_v1')
        expect(result[:status]).to eq('active')
      end

      it 'returns test plan information' do
        logic = create_logic(planid: 'identity_v1')

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(result[:status]).to eq('active')
        expect(result[:test_planid]).to eq('identity_v1')
        expect(result[:test_plan_name]).to eq('Identity Plus')
        expect(result[:actual_planid]).to eq('free')
        expect(result[:entitlements]).to include('custom_domains')
        expect(result[:entitlements]).to include('create_team')
      end

      it 'returns all entitlements for test plan' do
        logic = create_logic(planid: 'multi_team_v1')

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(result[:entitlements]).to include('api_access')
        expect(result[:entitlements]).to include('audit_logs')
        expect(result[:entitlements]).to include('advanced_analytics')
      end

      it 'allows testing lower tier plans' do
        # Colonel on identity_v1 testing as free
        allow(organization).to receive(:planid).and_return('identity_v1')

        logic = create_logic(planid: 'free')

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(result[:status]).to eq('active')
        expect(result[:test_planid]).to eq('free')
        expect(result[:actual_planid]).to eq('identity_v1')
        expect(result[:entitlements]).to match_array(%w[create_secrets basic_sharing])
      end
    end

    context 'clearing test mode' do
      before do
        # Pre-set test mode in session
        session_data[:entitlement_test_planid] = 'identity_v1'
      end

      it 'clears test planid with null' do
        logic = create_logic(planid: nil)

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(session_data[:entitlement_test_planid]).to be_nil
        expect(result[:status]).to eq('cleared')
      end

      it 'clears test planid with empty string' do
        logic = create_logic(planid: '')

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(session_data[:entitlement_test_planid]).to be_nil
        expect(result[:status]).to eq('cleared')
      end

      it 'returns actual planid when cleared' do
        logic = create_logic(planid: nil)

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(result[:status]).to eq('cleared')
        expect(result[:actual_planid]).to eq('free')
      end

      it 'does not return test plan info when cleared' do
        logic = create_logic(planid: nil)

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(result).not_to have_key(:test_planid)
        expect(result).not_to have_key(:test_plan_name)
        expect(result).not_to have_key(:entitlements)
      end
    end

    context 'validation' do
      it 'raises error for invalid plan ID' do
        logic = create_logic(planid: 'nonexistent_plan')

        logic.process_params

        expect {
          logic.raise_concerns
        }.to raise_error(OT::FormError, /Invalid plan ID/)
      end

      it 'handles whitespace in planid' do
        logic = create_logic(planid: '  identity_v1  ')

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(session_data[:entitlement_test_planid]).to eq('identity_v1')
        expect(result[:status]).to eq('active')
      end

      it 'treats empty whitespace as clearing' do
        session_data[:entitlement_test_planid] = 'identity_v1'

        logic = create_logic(planid: '   ')

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(session_data[:entitlement_test_planid]).to be_nil
        expect(result[:status]).to eq('cleared')
      end
    end

    context 'authorization' do
      it 'requires colonel role' do
        # Mock non-colonel customer
        non_colonel = double(
          'Customer',
          custid: 'user@example.com',
          role: 'customer',
          colonel?: false,
        )

        # Create properly mocked session
        session = double('Session')
        allow(session).to receive(:[]).with(:entitlement_test_planid).and_return(nil)
        allow(session).to receive(:[]=)
        allow(session).to receive(:delete)

        # Create strategy_result mock (this is what Logic::Base#initialize expects)
        strategy_result = double('StrategyResult')
        allow(strategy_result).to receive(:session).and_return(session)
        allow(strategy_result).to receive(:user).and_return(non_colonel)
        allow(strategy_result).to receive(:metadata).and_return({ organization: organization })

        logic = ColonelAPI::Logic::Colonel::SetEntitlementTest.new(
          strategy_result,
          { planid: 'identity_v1' },
        )

        # Mock organization method
        allow(logic).to receive(:organization).and_return(organization)

        # Mock verify_one_of_roles! to actually check
        allow(logic).to receive(:verify_one_of_roles!) do |roles|
          raise OT::Unauthorized unless roles[:colonel] && non_colonel.colonel?
        end

        logic.process_params

        expect {
          logic.raise_concerns
        }.to raise_error(OT::Unauthorized)
      end

      it 'allows colonel to set test mode' do
        logic = create_logic(planid: 'identity_v1')

        logic.process_params

        expect {
          logic.raise_concerns
        }.not_to raise_error
      end
    end

    context 'session persistence' do
      it 'persists test planid across multiple requests' do
        # First request: set test mode
        logic1 = create_logic(planid: 'identity_v1')
        logic1.process_params
        logic1.raise_concerns
        logic1.process

        # Simulate new request with same session
        logic2 = create_logic(planid: 'multi_team_v1')

        # Session should still have previous value until process runs
        expect(session_data[:entitlement_test_planid]).to eq('identity_v1')

        # Second request: change test mode
        logic2.process_params
        logic2.raise_concerns
        logic2.process

        expect(session_data[:entitlement_test_planid]).to eq('multi_team_v1')
      end

      it 'clears on logout (simulated)' do
        logic = create_logic(planid: 'identity_v1')
        logic.process_params
        logic.raise_concerns
        logic.process

        # Simulate logout by clearing session
        session_data.clear

        expect(session_data[:entitlement_test_planid]).to be_nil
      end
    end

    context 'plan switching' do
      it 'switches from one test plan to another' do
        # Set identity_v1
        logic1 = create_logic(planid: 'identity_v1')
        logic1.process_params
        logic1.raise_concerns
        result1 = logic1.process

        expect(result1[:test_planid]).to eq('identity_v1')

        # Switch to multi_team_v1
        logic2 = create_logic(planid: 'multi_team_v1')
        logic2.process_params
        logic2.raise_concerns
        result2 = logic2.process

        expect(result2[:test_planid]).to eq('multi_team_v1')
        expect(session_data[:entitlement_test_planid]).to eq('multi_team_v1')
      end

      it 'switches from test mode to cleared' do
        # Set test mode
        logic1 = create_logic(planid: 'identity_v1')
        logic1.process_params
        logic1.raise_concerns
        logic1.process

        # Clear test mode
        logic2 = create_logic(planid: nil)
        logic2.process_params
        logic2.raise_concerns
        result2 = logic2.process

        expect(result2[:status]).to eq('cleared')
        expect(session_data[:entitlement_test_planid]).to be_nil
      end
    end

    context 'edge cases' do
      it 'handles nil organization gracefully' do
        logic = create_logic(planid: 'identity_v1')
        allow(logic).to receive(:organization).and_return(nil)

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(result[:actual_planid]).to be_nil
      end

      it 'sets test mode even without organization' do
        logic = create_logic(planid: 'identity_v1')
        allow(logic).to receive(:organization).and_return(nil)

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(session_data[:entitlement_test_planid]).to eq('identity_v1')
        expect(result[:status]).to eq('active')
      end

      it 'handles all three available plans' do
        %w[free identity_v1 multi_team_v1].each do |planid|
          session_data.clear

          logic = create_logic(planid: planid)
          logic.process_params
          logic.raise_concerns
          result = logic.process

          expect(result[:status]).to eq('active')
          expect(result[:test_planid]).to eq(planid)
          expect(session_data[:entitlement_test_planid]).to eq(planid)
        end
      end
    end

    context 'response structure' do
      it 'includes all required fields when setting test mode' do
        logic = create_logic(planid: 'identity_v1')

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(result).to have_key(:status)
        expect(result).to have_key(:test_planid)
        expect(result).to have_key(:test_plan_name)
        expect(result).to have_key(:actual_planid)
        expect(result).to have_key(:entitlements)
      end

      it 'includes only required fields when clearing' do
        session_data[:entitlement_test_planid] = 'identity_v1'

        logic = create_logic(planid: nil)

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(result).to have_key(:status)
        expect(result).to have_key(:actual_planid)
        expect(result.keys.size).to eq(2)
      end

      it 'returns entitlements as array' do
        logic = create_logic(planid: 'identity_v1')

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(result[:entitlements]).to be_an(Array)
        expect(result[:entitlements]).not_to be_empty
      end

      it 'returns plan names as strings' do
        logic = create_logic(planid: 'identity_v1')

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(result[:test_plan_name]).to be_a(String)
        expect(result[:test_plan_name]).to eq('Identity Plus')
      end
    end
  end

  describe 'integration with WithEntitlements' do
    it 'test mode affects entitlement checks (when middleware sets Thread.current)' do
      # This documents the full flow:
      # 1. API sets session[:entitlement_test_planid]
      # 2. Middleware copies to Thread.current[:entitlement_test_planid]
      # 3. WithEntitlements#entitlements uses Thread.current override

      logic = create_logic(planid: 'identity_v1')
      logic.process_params
      logic.raise_concerns
      logic.process

      # Session has the override
      expect(session_data[:entitlement_test_planid]).to eq('identity_v1')

      # Middleware would copy this to Thread.current (simulated here)
      Thread.current[:entitlement_test_planid] = session_data[:entitlement_test_planid]

      # Now WithEntitlements would use the override
      # (This would be the organization model in real use)
      test_class = Class.new do
        include Onetime::Models::Features::WithEntitlements
        attr_accessor :planid
        def initialize(planid)
          @planid = planid
        end
      end

      org = test_class.new('free')
      expect(org.can?('custom_domains')).to be true # override in effect

      # Cleanup
      Thread.current[:entitlement_test_planid] = nil
    end
  end
end
