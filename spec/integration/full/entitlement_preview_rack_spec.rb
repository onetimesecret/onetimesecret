# spec/integration/full/entitlement_preview_rack_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Load the ColonelAPI application and its dependencies
# apps/api is in the load path from spec_helper
require 'colonel/application'

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
