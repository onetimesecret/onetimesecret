# spec/integration/all/entitlement_preview_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Load the ColonelAPI application and its dependencies
# apps/api is in the load path from spec_helper
require 'colonel/application'

# Integration tests for Colonel Entitlement Test Mode API
#
# Tests the /api/colonel/entitlement-preview endpoint that allows colonels
# to override their organization's plan entitlements for testing purposes.
#
# Requires:
# - Full OT boot (for apps/api/colonel)
# - Billing enabled with test plans
# - Session middleware
# - Organization with colonel customer
#
RSpec.describe 'ColonelAPI::Logic::Colonel::SetEntitlementPreview', type: :integration, billing: true do
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
    allow(session).to receive(:id).and_return('test_session_123')
    allow(session).to receive(:[]).with(:entitlement_preview_planid) { session_data[:entitlement_preview_planid] }
    allow(session).to receive(:[]).with(:entitlement_preview_grants_key) { session_data[:entitlement_preview_grants_key] }
    allow(session).to receive(:[]).with(:entitlement_preview_revokes_key) { session_data[:entitlement_preview_revokes_key] }
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
    logic = ColonelAPI::Logic::Colonel::SetEntitlementPreview.new(
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

    # The logic mirrors its session writes into the request's Fiber-local
    # (same-request visibility); outside the middleware there is no ensure
    # block, so clear it here to keep examples isolated.
    Onetime::EntitlementPreview.clear

    # Session override sets written to real Redis by set_test_mode
    Familia.dbclient.del(
      'session:test_session_123:entitlement_preview_grants',
      'session:test_session_123:entitlement_preview_revokes',
    )
  end

  describe 'POST /api/colonel/entitlement-preview' do
    context 'setting test mode' do
      it 'sets test planid in session' do
        logic = create_logic(planid: 'identity_v1')

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(session_data[:entitlement_preview_planid]).to eq('identity_v1')
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
        session_data[:entitlement_preview_planid] = 'identity_v1'
      end

      it 'clears test planid with null' do
        logic = create_logic(planid: nil)

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(session_data[:entitlement_preview_planid]).to be_nil
        expect(result[:status]).to eq('cleared')
      end

      it 'clears test planid with empty string' do
        logic = create_logic(planid: '')

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(session_data[:entitlement_preview_planid]).to be_nil
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

        expect(session_data[:entitlement_preview_planid]).to eq('identity_v1')
        expect(result[:status]).to eq('active')
      end

      it 'treats empty whitespace as clearing' do
        session_data[:entitlement_preview_planid] = 'identity_v1'

        logic = create_logic(planid: '   ')

        logic.process_params
        logic.raise_concerns
        result = logic.process

        expect(session_data[:entitlement_preview_planid]).to be_nil
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
        allow(session).to receive(:[]).with(:entitlement_preview_planid).and_return(nil)
        allow(session).to receive(:[]=)
        allow(session).to receive(:delete)

        # Create strategy_result mock (this is what Logic::Base#initialize expects)
        strategy_result = double('StrategyResult')
        allow(strategy_result).to receive(:session).and_return(session)
        allow(strategy_result).to receive(:user).and_return(non_colonel)
        allow(strategy_result).to receive(:metadata).and_return({ organization: organization })

        logic = ColonelAPI::Logic::Colonel::SetEntitlementPreview.new(
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
        expect(session_data[:entitlement_preview_planid]).to eq('identity_v1')

        # Second request: change test mode
        logic2.process_params
        logic2.raise_concerns
        logic2.process

        expect(session_data[:entitlement_preview_planid]).to eq('multi_team_v1')
      end

      it 'clears on logout (simulated)' do
        logic = create_logic(planid: 'identity_v1')
        logic.process_params
        logic.raise_concerns
        logic.process

        # Simulate logout by clearing session
        session_data.clear

        expect(session_data[:entitlement_preview_planid]).to be_nil
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
        expect(session_data[:entitlement_preview_planid]).to eq('multi_team_v1')
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
        expect(session_data[:entitlement_preview_planid]).to be_nil
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

        expect(session_data[:entitlement_preview_planid]).to eq('identity_v1')
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
          expect(session_data[:entitlement_preview_planid]).to eq(planid)
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
        session_data[:entitlement_preview_planid] = 'identity_v1'

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

  describe 'integration with the entitlement chokepoints (ADR-020)' do
    # The chokepoint contract: consumers call org.entitlements / org.limit_for
    # with no session parameter; the override arrives through the Fiber-local
    # populated by middleware (per request) and mirrored by this logic
    # (same-request visibility).
    it 'setting a preview populates the request-scoped context' do
      logic = create_logic(planid: 'identity_v1')
      logic.process_params
      logic.raise_concerns
      logic.process

      ctx = Onetime::EntitlementPreview.context
      expect(ctx).not_to be_nil
      expect(ctx[:planid]).to eq('identity_v1')
      expect(ctx[:grants_key]).to eq('session:test_session_123:entitlement_preview_grants')
      expect(ctx[:revokes_key]).to eq('session:test_session_123:entitlement_preview_revokes')
    end

    it 'limit_for resolves through the still-active context after the flip' do
      logic = create_logic(planid: 'identity_v1')
      logic.process_params
      logic.raise_concerns
      logic.process

      # Plain plan-chain host (no session parameter anywhere)
      test_class = Class.new do
        include Onetime::Models::Features::WithEntitlements
        include Onetime::Models::Features::WithMaterializedLimits
        include Onetime::Models::Features::WithPlanEntitlements
        attr_accessor :planid, :extid

        def initialize(planid)
          @planid = planid
          @extid  = 'test_preview_integration'
        end

        def billing_enabled?
          true
        end
      end

      org = test_class.new('free')

      # limit_for consults the preview planid; actual plan would give 0
      expect(org.limit_for('teams')).to eq(1)
    end

    it 'clearing the preview clears the request-scoped context' do
      logic1 = create_logic(planid: 'identity_v1')
      logic1.process_params
      logic1.raise_concerns
      logic1.process

      expect(Onetime::EntitlementPreview.active?).to be true

      logic2 = create_logic(planid: nil)
      logic2.process_params
      logic2.raise_concerns
      logic2.process

      expect(Onetime::EntitlementPreview.context).to be_nil
    end
  end
end

# End-to-end coverage of the request-scoped preview through the real rack
# stack (ADR-020): session middleware -> EntitlementPreviewContext ->
# handlers -> serializers, with real Customer/Organization/Membership models
# and real session override sets in Redis.
#
# These are the regressions the chokepoint design exists to prevent: the
# banner saying "testing with Team Plus" while /api/organizations serves the
# actual plan, and per-member divergence in the permissions payload.
RSpec.describe 'Entitlement preview through the rack stack (ADR-020)', type: :integration, billing: true do
  include Rack::Test::Methods

  before(:all) do
    ENV['AUTHENTICATION_MODE'] = 'full'

    # Reset registries to clear state from previous test runs
    Onetime::Application::Registry.reset!

    # Reload auth config to pick up AUTHENTICATION_MODE env var
    Onetime.auth_config.reload!

    # Boot application
    Onetime.boot! :test

    # Prepare registry
    Onetime::Application::Registry.prepare_application_registry
  end

  after(:all) do
    ENV.delete('AUTHENTICATION_MODE')
  end

  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  let(:run_id) { "adr020_#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }

  let(:free_entitlements)      { %w[create_secrets basic_sharing] }
  let(:identity_entitlements)  { %w[create_secrets basic_sharing custom_domains create_team priority_support] }
  let(:multi_team_entitlements) { %w[create_secrets basic_sharing custom_domains create_teams api_access audit_logs advanced_analytics] }

  before do
    BillingTestHelpers.populate_test_plans([
      {
        plan_id: 'free',
        name: 'Free',
        tier: 1,
        interval: 'month',
        region: 'us',
        entitlements: free_entitlements,
        limits: { 'teams.max' => '0' },
      },
      {
        plan_id: 'identity_v1',
        name: 'Identity Plus',
        tier: 2,
        interval: 'month',
        region: 'us',
        entitlements: identity_entitlements,
        limits: { 'teams.max' => '1' },
      },
      {
        plan_id: 'multi_team_v1',
        name: 'Multi-Team',
        tier: 3,
        interval: 'month',
        region: 'us',
        entitlements: multi_team_entitlements,
        limits: { 'teams.max' => 'unlimited' },
      },
    ])
  end

  # Colonel customer: role gate for /api/colonel requires role='colonel' AND
  # a verified email (defense-in-depth in authorization_policies.rb).
  let!(:colonel) do
    customer = Onetime::Customer.create!(email: "#{run_id}_colonel@test.com")
    customer.role     = 'colonel'
    customer.verified = 'true'
    customer.save
    customer
  end

  # Billing-mode org, deliberately NOT materialized: entitlement resolution
  # goes through the Plan.load fallback branch in WithPlanEntitlements —
  # the branch that returns without reaching super, where a base-only
  # preview guard would be skipped (the MRO regression).
  let!(:organization) do
    org = Onetime::Organization.create!("Preview Org #{run_id}", colonel, "#{run_id}_org@test.com")
    org.planid = 'free'
    org.save
    org
  end

  # Owner membership, MATERIALIZED from the actual plan: during preview the
  # materialized set must be ignored (org ∩ role recomputed), identically to
  # an unmaterialized membership.
  let!(:owner_membership) do
    membership = Onetime::OrganizationMembership.find_by_org_customer(organization.objid, colonel.objid)
    membership&.materialize_for_role!(organization)
    membership
  end

  let!(:custom_domain) do
    domain                = Onetime::CustomDomain.new
    domain.display_domain = "#{run_id}.example.com"
    domain.org_id         = organization.objid
    domain.save
    organization.domains.add(domain.objid)
    domain
  end

  # Session-scoped override sets (reset-and-substitute: revoke the actual
  # entitlements, grant the preview plan's)
  let(:preview_session_id) { "adr020sess#{SecureRandom.hex(8)}" }
  let(:grants_key)  { "session:#{preview_session_id}:entitlement_preview_grants" }
  let(:revokes_key) { "session:#{preview_session_id}:entitlement_preview_revokes" }

  def seed_preview_sets(grants:, revokes:)
    redis = Familia.dbclient
    redis.sadd(grants_key, grants) if grants.any?
    redis.sadd(revokes_key, revokes) if revokes.any?
  end

  def base_session
    {
      'external_id' => colonel.extid,
      'authenticated' => true,
      'session_id' => preview_session_id,
    }
  end

  def preview_session(planid:)
    base_session.merge(
      'entitlement_preview_planid' => planid,
      'entitlement_preview_grants_key' => grants_key,
      'entitlement_preview_revokes_key' => revokes_key,
    )
  end

  after do
    Onetime::EntitlementPreview.clear
    Familia.dbclient.del(grants_key, revokes_key)
    custom_domain&.destroy! rescue nil
    owner_membership&.destroy! rescue nil
    organization&.destroy! rescue nil
    colonel&.destroy! rescue nil
  end

  describe 'GET /api/organizations' do
    it 'serves the actual plan entitlements and limits without a preview' do
      env 'rack.session', base_session

      get '/api/organizations'

      expect(last_response.status).to eq(200)
      body   = JSON.parse(last_response.body)
      record = body['records'].find { |r| r['extid'] == organization.extid }
      expect(record).not_to be_nil
      expect(record['entitlements']).to match_array(free_entitlements)
      expect(record['limits']['teams']).to eq(0)
    end

    it 'serves the PREVIEW entitlements and limits during an active preview' do
      seed_preview_sets(grants: identity_entitlements, revokes: free_entitlements)
      env 'rack.session', preview_session(planid: 'identity_v1')

      get '/api/organizations'

      expect(last_response.status).to eq(200)
      body   = JSON.parse(last_response.body)
      record = body['records'].find { |r| r['extid'] == organization.extid }
      expect(record).not_to be_nil
      expect(record['entitlements']).to match_array(identity_entitlements)
      expect(record['limits']['teams']).to eq(1)
    end

    it 'clears the Fiber-local after the request completes' do
      seed_preview_sets(grants: identity_entitlements, revokes: free_entitlements)
      env 'rack.session', preview_session(planid: 'identity_v1')

      get '/api/organizations'

      expect(last_response.status).to eq(200)
      expect(Onetime::EntitlementPreview.context).to be_nil
    end

    it 'clears the Fiber-local when the handler raises' do
      seed_preview_sets(grants: identity_entitlements, revokes: free_entitlements)
      env 'rack.session', preview_session(planid: 'identity_v1')

      allow_any_instance_of(OrganizationAPI::Logic::Organizations::ListOrganizations)
        .to receive(:process).and_raise(RuntimeError, 'boom')

      begin
        get '/api/organizations'
      rescue RuntimeError
        # Depending on error-handler coverage the exception may propagate
        # through Rack::Test; either way the ensure-clear must have run.
      end

      expect(Onetime::EntitlementPreview.context).to be_nil
    end
  end

  describe 'GET /api/account/permissions' do
    it 'serves membership entitlements from the actual plan without a preview' do
      env 'rack.session', base_session

      get '/api/account/permissions'

      expect(last_response.status).to eq(200)
      body     = JSON.parse(last_response.body)
      org_data = body['organizations'].find { |o| o['extid'] == organization.extid }
      expect(org_data).not_to be_nil

      # free plan has no custom_domains, so the owner's materialized set
      # lacks it and domain permissions are denied
      expect(org_data['membership']['entitlements']).not_to include('custom_domains')
      domain_data = org_data['domains'].find { |d| d['extid'] == custom_domain.extid }
      expect(domain_data['permissions']['can_view']).to be false
    end

    it 'flips the payload for a MATERIALIZED membership during a preview' do
      seed_preview_sets(grants: identity_entitlements, revokes: free_entitlements)
      env 'rack.session', preview_session(planid: 'identity_v1')

      get '/api/account/permissions'

      expect(last_response.status).to eq(200)
      body     = JSON.parse(last_response.body)
      org_data = body['organizations'].find { |o| o['extid'] == organization.extid }
      expect(org_data).not_to be_nil

      # org ∩ owner-role over the preview-aware org: the materialized set is
      # ignored, custom_domains (identity_v1) shows up, and the role template
      # masks plan entitlements outside it (e.g. priority_support)
      expect(org_data['membership']['entitlements']).to include('custom_domains')
      expect(org_data['membership']['entitlements']).not_to include('priority_support')
      domain_data = org_data['domains'].find { |d| d['extid'] == custom_domain.extid }
      expect(domain_data['permissions']['can_view']).to be true
    end
  end

  describe 'same-request visibility (handler mirrors the Fiber-local)' do
    # Real logic + real org, invoked directly: the middleware stashes the
    # PRE-flip context before the handler runs, so SetEntitlementPreview must
    # mirror its session writes into the Fiber-local for the flipping
    # request's own response to reflect the new state.
    let(:logic_session_id) { "adr020logic#{SecureRandom.hex(8)}" }

    let(:logic_session) do
      session = {}
      sid     = logic_session_id
      session.define_singleton_method(:id) { sid }
      session
    end

    # Materialized org with a marker entitlement absent from every preview
    # plan, so a revokes baseline computed from a reconciled (preview) view
    # instead of actual state is observable as a leak.
    let!(:materialized_org) do
      org = Onetime::Organization.create!("Preview Flip Org #{run_id}", colonel, "#{run_id}_flip@test.com")
      org.planid = 'free'
      org.save
      org.materialize_entitlements_from_config(
        entitlements: free_entitlements + ['workspace_branding'],
        limits: {},
      )
      org
    end

    def build_preview_logic(planid:)
      strategy_result = Otto::Security::Authentication::StrategyResult.new(
        session: logic_session,
        user: colonel,
        auth_method: 'sessionauth',
        strategy_name: 'sessionauth',
        metadata: { ip: '127.0.0.1' },
      )
      logic = ColonelAPI::Logic::Colonel::SetEntitlementPreview.new(
        strategy_result,
        { 'planid' => planid },
      )
      allow(logic).to receive(:organization).and_return(materialized_org)
      logic.process_params
      logic.raise_concerns
      logic
    end

    after do
      Onetime::EntitlementPreview.clear
      Familia.dbclient.del(
        "session:#{logic_session_id}:entitlement_preview_grants",
        "session:#{logic_session_id}:entitlement_preview_revokes",
      )
      materialized_org&.destroy! rescue nil
    end

    it 'the request that sets the preview already resolves through it' do
      expect(materialized_org.entitlements).to match_array(free_entitlements + ['workspace_branding'])

      build_preview_logic(planid: 'identity_v1').process

      expect(Onetime::EntitlementPreview.context[:planid]).to eq('identity_v1')
      expect(materialized_org.entitlements).to match_array(identity_entitlements)
    end

    it 'the request that clears the preview already resolves without it' do
      build_preview_logic(planid: 'identity_v1').process
      expect(materialized_org.entitlements).to match_array(identity_entitlements)

      build_preview_logic(planid: nil).process

      expect(Onetime::EntitlementPreview.context).to be_nil
      expect(materialized_org.entitlements).to match_array(free_entitlements + ['workspace_branding'])
    end

    it 'switching previews computes the revokes baseline from ACTUAL entitlements' do
      build_preview_logic(planid: 'identity_v1').process

      # The Fiber-local still carries preview A here (as it would mid-request
      # after the middleware stash); reading the baseline through it would
      # compute revokes from A's reconciled view and leak actual-only
      # entitlements through preview B.
      build_preview_logic(planid: 'multi_team_v1').process

      expect(materialized_org.entitlements).to match_array(multi_team_entitlements)
      expect(materialized_org.entitlements).not_to include('workspace_branding')
    end
  end

  describe 'POST /api/colonel/entitlement-preview through the stack' do
    it 'activates a preview that the next request serves, then clears the Fiber-local' do
      env 'rack.session', base_session

      post '/api/colonel/entitlement-preview',
        { planid: 'identity_v1' }.to_json,
        'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(200)
      # ensure-clear ran after the flipping request too
      expect(Onetime::EntitlementPreview.context).to be_nil

      # The session now carries the preview keys (real session store via the
      # cookie jar); the next request resolves through them.
      get '/api/organizations'

      expect(last_response.status).to eq(200)
      body   = JSON.parse(last_response.body)
      record = body['records'].find { |r| r['extid'] == organization.extid }
      expect(record['entitlements']).to match_array(identity_entitlements)
    end
  end
end
