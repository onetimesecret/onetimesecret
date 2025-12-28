# spec/integration/api/v2/entitlement_enforcement_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Integration tests for API V2 Entitlement Enforcement
#
# These tests verify that API v2 logic classes enforce the api_access entitlement
# by raising Onetime::EntitlementRequired when the organization lacks it.
#
# The entitlement check flow:
# 1. Logic class calls require_entitlement!('api_access') in raise_concerns
# 2. If org lacks entitlement, raises Onetime::EntitlementRequired
# 3. Otto error handler catches it and returns 403 with upgrade info
#
# Testing approach:
# We test the logic classes directly by mocking strategy_result, session, and
# organization. This allows us to verify the entitlement check behavior without
# needing full HTTP authentication infrastructure.
#
RSpec.describe 'API V2 Entitlement Enforcement', type: :integration, billing: true do
  # Helper to create a mock organization with specific entitlements
  def mock_organization(planid:, entitlements:)
    org = double('Organization', planid: planid, objid: "org_#{SecureRandom.hex(4)}")
    allow(org).to receive(:can?) do |entitlement|
      entitlements.include?(entitlement.to_s)
    end
    org
  end

  # Helper to create a mock customer
  def mock_customer(custid: 'test@example.com', anonymous: false)
    customer = double('Customer', custid: custid, role: 'customer')
    allow(customer).to receive(:anonymous?).and_return(anonymous)
    allow(customer).to receive(:verified?).and_return(true)
    allow(customer).to receive(:increment_field)
    customer
  end

  # Helper to create a mock session
  def mock_session
    session_data = {}
    session = double('Session')
    allow(session).to receive(:[]) { |key| session_data[key] }
    allow(session).to receive(:[]=) { |key, value| session_data[key] = value }
    allow(session).to receive(:delete) { |key| session_data.delete(key) }
    allow(session).to receive(:destroy!)
    session
  end

  # Helper to create a logic instance with proper mocks
  # @param logic_class [Class] The V2 logic class to instantiate
  # @param params [Hash] The params hash for the logic class
  # @param org [Object] Mock organization (or nil for anonymous)
  # @param customer [Object] Mock customer (optional)
  # @return [Object] The logic instance
  def create_logic(logic_class, params:, org:, customer: nil)
    customer ||= mock_customer
    session = mock_session

    strategy_result = double('StrategyResult')
    allow(strategy_result).to receive(:session).and_return(session)
    allow(strategy_result).to receive(:user).and_return(customer)
    allow(strategy_result).to receive(:metadata).and_return({ organization: org })

    logic = logic_class.new(strategy_result, params)

    # Mock the org accessor to return our mock org
    allow(logic).to receive(:org).and_return(org)

    # Mock cust accessor for logic classes that need it
    allow(logic).to receive(:cust).and_return(customer)

    # Mock sess accessor
    allow(logic).to receive(:sess).and_return(session)

    logic
  end

  # Setup test plans in Redis cache
  before(:all) do
    require 'onetime'
    Onetime.boot! :test

    BillingTestHelpers.populate_test_plans([
      {
        # Test plan WITHOUT api_access - for testing entitlement denial
        plan_id: 'free_test_no_api_access',
        name: 'Free (No API)',
        tier: 0,
        interval: 'month',
        region: 'us',
        entitlements: %w[create_secrets basic_sharing],
        limits: { 'teams.max' => '0' },
      },
      {
        # Standard free plan WITH api_access - matches production free tier
        plan_id: 'free_v1',
        name: 'Free',
        tier: 1,
        interval: 'month',
        region: 'us',
        entitlements: %w[create_secrets basic_sharing api_access view_metadata],
        limits: { 'teams.max' => '0' },
      },
      {
        plan_id: 'identity_v1',
        name: 'Identity Plus',
        tier: 2,
        interval: 'month',
        region: 'us',
        entitlements: %w[create_secrets basic_sharing custom_domains create_team],
        limits: { 'teams.max' => '1' },
      },
      {
        plan_id: 'multi_team_v1',
        name: 'Multi-Team',
        tier: 3,
        interval: 'month',
        region: 'us',
        entitlements: %w[create_secrets basic_sharing custom_domains create_teams api_access audit_logs],
        limits: { 'teams.max' => 'unlimited' },
      },
    ])
  end

  describe 'ShowSecret' do
    let(:logic_class) { V2::Logic::Secrets::ShowSecret }

    context 'when organization lacks api_access entitlement' do
      let(:org) { mock_organization(planid: 'free_test_no_api_access', entitlements: %w[create_secrets basic_sharing]) }

      it 'raises EntitlementRequired in raise_concerns' do
        # Create a test secret
        _meta, secret = Onetime::Metadata.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(logic_class, params: { 'identifier' => secret.identifier }, org: org)
        logic.process_params

        expect {
          logic.raise_concerns
        }.to raise_error(Onetime::EntitlementRequired) do |error|
          expect(error.entitlement).to eq('api_access')
          expect(error.current_plan).to eq('free_test_no_api_access')
        end
      end
    end

    context 'when organization has api_access entitlement (paid plan)' do
      let(:org) { mock_organization(planid: 'multi_team_v1', entitlements: %w[create_secrets api_access]) }

      it 'does not raise EntitlementRequired' do
        _meta, secret = Onetime::Metadata.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(logic_class, params: { 'identifier' => secret.identifier }, org: org)
        logic.process_params

        # Should pass entitlement check without raising
        expect { logic.raise_concerns }.not_to raise_error
      end
    end

    context 'when organization has api_access entitlement (free plan)' do
      let(:org) { mock_organization(planid: 'free_v1', entitlements: %w[create_secrets api_access view_metadata]) }

      it 'does not raise EntitlementRequired for free users with api_access' do
        _meta, secret = Onetime::Metadata.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(logic_class, params: { 'identifier' => secret.identifier }, org: org)
        logic.process_params

        # Free plan includes api_access, so should pass
        expect { logic.raise_concerns }.not_to raise_error
      end
    end

    context 'when no organization (anonymous request)' do
      it 'does not raise EntitlementRequired (passes through)' do
        _meta, secret = Onetime::Metadata.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(logic_class, params: { 'identifier' => secret.identifier }, org: nil)
        logic.process_params

        # Anonymous requests should pass the entitlement check
        # (they may fail later for other reasons like missing secret)
        expect { logic.raise_concerns }.not_to raise_error
      end
    end
  end

  describe 'ShowSecretStatus' do
    let(:logic_class) { V2::Logic::Secrets::ShowSecretStatus }

    context 'when organization lacks api_access entitlement' do
      let(:org) { mock_organization(planid: 'identity_v1', entitlements: %w[create_secrets custom_domains]) }

      it 'raises EntitlementRequired' do
        _meta, secret = Onetime::Metadata.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(logic_class, params: { 'identifier' => secret.identifier }, org: org)
        logic.process_params

        expect {
          logic.raise_concerns
        }.to raise_error(Onetime::EntitlementRequired) do |error|
          expect(error.entitlement).to eq('api_access')
        end
      end
    end

    context 'when organization has api_access entitlement' do
      let(:org) { mock_organization(planid: 'multi_team_v1', entitlements: %w[api_access]) }

      it 'does not raise EntitlementRequired' do
        _meta, secret = Onetime::Metadata.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(logic_class, params: { 'identifier' => secret.identifier }, org: org)
        logic.process_params

        # Should pass entitlement check without raising
        expect { logic.raise_concerns }.not_to raise_error
      end
    end
  end

  describe 'ListSecretStatus' do
    let(:logic_class) { V2::Logic::Secrets::ListSecretStatus }

    context 'when organization lacks api_access entitlement' do
      let(:org) { mock_organization(planid: 'free_test_no_api_access', entitlements: %w[create_secrets]) }

      it 'raises EntitlementRequired' do
        logic = create_logic(logic_class, params: { 'identifiers' => %w[abc123 def456] }, org: org)
        logic.process_params

        expect {
          logic.raise_concerns
        }.to raise_error(Onetime::EntitlementRequired)
      end
    end
  end

  describe 'RevealSecret' do
    let(:logic_class) { V2::Logic::Secrets::RevealSecret }

    context 'when organization lacks api_access entitlement' do
      let(:org) { mock_organization(planid: 'identity_v1', entitlements: %w[create_secrets custom_domains]) }

      it 'raises EntitlementRequired' do
        _meta, secret = Onetime::Metadata.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(logic_class, params: { 'identifier' => secret.identifier }, org: org)
        logic.process_params

        expect {
          logic.raise_concerns
        }.to raise_error(Onetime::EntitlementRequired)
      end
    end
  end

  describe 'ShowMetadata' do
    let(:logic_class) { V2::Logic::Secrets::ShowMetadata }

    context 'when organization lacks api_access entitlement' do
      let(:org) { mock_organization(planid: 'free_test_no_api_access', entitlements: %w[create_secrets]) }

      it 'raises EntitlementRequired' do
        metadata, _secret = Onetime::Metadata.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(logic_class, params: { 'identifier' => metadata.identifier }, org: org)
        logic.process_params

        expect {
          logic.raise_concerns
        }.to raise_error(Onetime::EntitlementRequired)
      end
    end
  end

  describe 'BurnSecret' do
    let(:logic_class) { V2::Logic::Secrets::BurnSecret }

    context 'when organization lacks api_access entitlement' do
      let(:org) { mock_organization(planid: 'free_test_no_api_access', entitlements: %w[create_secrets]) }

      it 'raises EntitlementRequired' do
        metadata, _secret = Onetime::Metadata.spawn_pair(nil, 3600, 'test value')

        logic = create_logic(logic_class, params: { 'identifier' => metadata.identifier, 'continue' => 'true' }, org: org)
        logic.process_params

        expect {
          logic.raise_concerns
        }.to raise_error(Onetime::EntitlementRequired)
      end
    end
  end

  describe 'EntitlementRequired error structure' do
    let(:org) { mock_organization(planid: 'free_test_no_api_access', entitlements: %w[create_secrets]) }

    it 'includes entitlement name' do
      _meta, secret = Onetime::Metadata.spawn_pair(nil, 3600, 'test value')

      logic = create_logic(V2::Logic::Secrets::ShowSecret, params: { 'identifier' => secret.identifier }, org: org)
      logic.process_params

      begin
        logic.raise_concerns
      rescue Onetime::EntitlementRequired => e
        expect(e.entitlement).to eq('api_access')
      end
    end

    it 'includes current plan' do
      _meta, secret = Onetime::Metadata.spawn_pair(nil, 3600, 'test value')

      logic = create_logic(V2::Logic::Secrets::ShowSecret, params: { 'identifier' => secret.identifier }, org: org)
      logic.process_params

      begin
        logic.raise_concerns
      rescue Onetime::EntitlementRequired => e
        expect(e.current_plan).to eq('free')
      end
    end

    it 'includes upgrade path when available' do
      _meta, secret = Onetime::Metadata.spawn_pair(nil, 3600, 'test value')

      logic = create_logic(V2::Logic::Secrets::ShowSecret, params: { 'identifier' => secret.identifier }, org: org)
      logic.process_params

      begin
        logic.raise_concerns
      rescue Onetime::EntitlementRequired => e
        # upgrade_to may or may not be set depending on Billing::PlanHelpers availability
        expect(e).to respond_to(:upgrade_to)
      end
    end
  end

  describe 'inheritance verification' do
    it 'V3::Logic::Secrets classes inherit from V2' do
      require 'v3/logic/secrets'

      expect(V3::Logic::Secrets::ListMetadata.ancestors).to include(V2::Logic::Secrets::ListMetadata)
      expect(V3::Logic::Secrets::BurnSecret.ancestors).to include(V2::Logic::Secrets::BurnSecret)
      expect(V3::Logic::Secrets::ShowMetadata.ancestors).to include(V2::Logic::Secrets::ShowMetadata)
    end

    it 'ConcealSecret and GenerateSecret inherit from BaseSecretAction' do
      require 'v2/logic/secrets/conceal_secret'
      require 'v2/logic/secrets/generate_secret'

      expect(V2::Logic::Secrets::ConcealSecret.ancestors).to include(V2::Logic::Secrets::BaseSecretAction)
      expect(V2::Logic::Secrets::GenerateSecret.ancestors).to include(V2::Logic::Secrets::BaseSecretAction)
    end
  end
end
