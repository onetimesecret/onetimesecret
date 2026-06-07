# spec/integration/api/v2/secret_ttl_entitlement_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Integration tests for API V2 TTL Entitlement Gate (#3074)
#
# Verifies that V2 BaseSecretAction#process_ttl enforces the
# `extended_default_expiration` entitlement at the DEFAULT_FREE_TTL
# boundary. V2's gate fires BEFORE clamping, so a request with
# `ttl > DEFAULT_FREE_TTL` raises Onetime::EntitlementRequired even
# when the org's plan would have clamped the request anyway.
#
# These tests cover BOTH ConcealSecret and GenerateSecret because the
# gate lives in the shared base class — coverage on each subclass guards
# against future divergence.
#
# A parallel V3 spec exists at
# spec/integration/api/v3/secret_ttl_entitlement_spec.rb and exercises
# the same matrix against V3 logic classes. Even when V3 inherits V2,
# the spec must exist on each version so that overriding `process_ttl`
# in one version cannot silently lose coverage on the other.
#
RSpec.describe 'API V2 Secret TTL Entitlement Gate', type: :integration, billing: true do
  FREE_TTL = Onetime::Models::Features::WithEntitlements::DEFAULT_FREE_TTL

  def mock_organization(planid:, entitlements:, secret_lifetime: FREE_TTL)
    org_id = "org_#{SecureRandom.hex(4)}"
    org = double('Organization', planid: planid, objid: org_id, extid: org_id)
    allow(org).to receive(:entitlements).and_return(entitlements)
    allow(org).to receive(:can?) do |entitlement|
      entitlements.include?(entitlement.to_s)
    end
    allow(org).to receive(:limit_for) do |resource|
      resource.to_s == 'secret_lifetime' ? secret_lifetime : 0
    end
    org
  end

  def mock_customer(custid: 'test@example.com', anonymous: false)
    customer = double('Customer', custid: custid, role: 'customer')
    allow(customer).to receive(:anonymous?).and_return(anonymous)
    allow(customer).to receive(:verified?).and_return(true)
    allow(customer).to receive(:increment_field)
    allow(customer).to receive(:objid).and_return(anonymous ? nil : 'cust_abc123')
    customer
  end

  def mock_session
    session_data = {}
    session = double('Session')
    allow(session).to receive(:[]) { |key| session_data[key] }
    allow(session).to receive(:[]=) { |key, value| session_data[key] = value }
    allow(session).to receive(:delete) { |key| session_data.delete(key) }
    allow(session).to receive(:destroy!)
    session
  end

  def create_logic(logic_class, params:, org:, customer: nil, auth_method: 'apikey')
    customer ||= mock_customer(anonymous: org.nil?)
    session = mock_session

    # Create membership mock for entitlement checks
    membership = nil
    if org
      membership = double('OrganizationMembership')
      allow(membership).to receive(:active?).and_return(true)
      allow(membership).to receive(:can?) do |entitlement|
        org.entitlements.include?(entitlement.to_s)
      end

      # Stub the class-level lookup BEFORE construction so auth_membership
      # finds the mock during process_params
      allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
        .with(org.objid, customer.objid)
        .and_return(membership)
    end

    # StrategyResult metadata uses organization_context nested structure
    org_context = { organization: org, organization_id: org&.objid }

    strategy_result = double('StrategyResult')
    allow(strategy_result).to receive(:session).and_return(session)
    allow(strategy_result).to receive(:user).and_return(customer)
    allow(strategy_result).to receive(:metadata).and_return(
      organization_context: org_context,
    )
    allow(strategy_result).to receive(:auth_method).and_return(auth_method)

    logic = logic_class.new(strategy_result, params)

    allow(logic).to receive(:cust).and_return(customer)
    allow(logic).to receive(:sess).and_return(session)
    logic
  end

  def stub_secret_options
    allow(OT).to receive(:conf).and_return(
      'site' => {
        'secret_options' => {
          'default_ttl' => 7 * 24 * 60 * 60,
          'ttl_options' => [60, 3600, 86_400, 604_800, 2_592_000, 7_776_000],
          'password_generation' => { 'default_length' => 12 },
        },
        'interface' => {
          'api' => {
            'guest_routes' => {
              'enabled' => true,
              'conceal' => true, 'generate' => true, 'reveal' => true,
              'burn' => true, 'show' => true, 'receipt' => true,
            },
          },
        },
      },
    )
  end

  before(:all) do
    require 'onetime'
    Onetime.boot! :test
  end

  before { stub_secret_options }

  shared_examples 'extended_default_expiration TTL gate' do |logic_class_proc|
    let(:logic_class) { logic_class_proc.call }

    def conceal_params(ttl)
      { 'secret' => { 'secret' => 'test value', 'ttl' => ttl.to_s } }
    end

    context 'when ttl is at or below DEFAULT_FREE_TTL' do
      let(:org) { mock_organization(planid: 'free_v1', entitlements: %w[create_secrets api_access], secret_lifetime: FREE_TTL) }

      it 'does not raise EntitlementRequired (ttl == DEFAULT_FREE_TTL boundary uses >, not >=)' do
        logic = create_logic(logic_class, params: conceal_params(FREE_TTL), org: org)
        expect { logic.process_params }.not_to raise_error
        expect(logic.ttl).to eq(FREE_TTL)
      end

      it 'does not raise for ttl below the boundary' do
        logic = create_logic(logic_class, params: conceal_params(FREE_TTL - 60), org: org)
        expect { logic.process_params }.not_to raise_error
        expect(logic.ttl).to eq(FREE_TTL - 60)
      end
    end

    context 'when ttl exceeds DEFAULT_FREE_TTL and org lacks the entitlement' do
      let(:org) { mock_organization(planid: 'free_v1', entitlements: %w[create_secrets api_access], secret_lifetime: FREE_TTL) }

      it 'raises EntitlementRequired with extended_default_expiration' do
        # process_params runs in constructor, so error is raised during create_logic
        expect {
          create_logic(logic_class, params: conceal_params(2_592_000), org: org)
        }.to raise_error(Onetime::EntitlementRequired) do |error|
          expect(error.entitlement).to eq('extended_default_expiration')
          expect(error.current_plan).to eq('free_v1')
        end
      end

      it 'fires BEFORE clamping (V2 contract: error, not silent clamp)' do
        # Even though plan_max would clamp the request to FREE_TTL, V2's
        # gate runs first and rejects. This is the key V2-vs-V1 difference.
        # process_params runs in constructor, so error is raised during create_logic
        expect {
          create_logic(logic_class, params: conceal_params(FREE_TTL + 1), org: org)
        }.to raise_error(Onetime::EntitlementRequired)
      end
    end

    context 'when ttl exceeds DEFAULT_FREE_TTL and org has the entitlement' do
      let(:org) do
        mock_organization(
          planid: 'identity_plus_v1',
          entitlements: %w[create_secrets api_access extended_default_expiration],
          secret_lifetime: 2_592_000,
        )
      end

      it 'does not raise and preserves the requested ttl' do
        logic = create_logic(logic_class, params: conceal_params(2_592_000), org: org)
        expect { logic.process_params }.not_to raise_error
        expect(logic.ttl).to eq(2_592_000)
      end

      it 'silently clamps when ttl exceeds the plan secret_lifetime ceiling' do
        logic = create_logic(logic_class, params: conceal_params(7_776_000), org: org)
        expect { logic.process_params }.not_to raise_error
        # 30 days global cap applies first (line 130: `@ttl = 30.days if ttl >= 30.days`)
        expect(logic.ttl).to eq(2_592_000)
      end
    end

    context 'when auth_org is nil (anonymous request)' do
      it 'bypasses the gate' do
        logic = create_logic(logic_class, params: conceal_params(2_592_000), org: nil, auth_method: 'noauth')
        expect { logic.process_params }.not_to raise_error
      end
    end

    # Regression suite for #3111 — DEFAULT_FREE_TTL drifted from the
    # free_v1 plan's 14-day secret_lifetime, so users on the free tier
    # were being told they could only set 7 days even though the plan
    # promises 14. These tests pin the customer-facing contract: any
    # request from 7 days + 1 second up to and including 14 days from a
    # free_v1 org with no extended_default_expiration entitlement must
    # succeed without an EntitlementRequired surprise.
    context '#3111 regression: free_v1 ceiling is 14 days, not 7 (no customer annoyance)' do
      let(:org) do
        mock_organization(
          planid: 'free_v1',
          entitlements: %w[create_secrets api_access],
          secret_lifetime: FREE_TTL,
        )
      end

      it 'accepts a TTL of exactly 14 days without raising' do
        logic = create_logic(logic_class, params: conceal_params(14 * 24 * 60 * 60), org: org)
        expect { logic.process_params }.not_to raise_error
        expect(logic.ttl).to eq(14 * 24 * 60 * 60)
      end

      it 'accepts a TTL of 10 days (above legacy 7-day cap, within new 14-day cap)' do
        ten_days = 10 * 24 * 60 * 60
        logic = create_logic(logic_class, params: conceal_params(ten_days), org: org)
        expect { logic.process_params }.not_to raise_error
        expect(logic.ttl).to eq(ten_days)
      end

      it 'accepts a TTL of 7 days + 1 second (used to fail with #3111)' do
        # Before the fix, this would clamp to 7 days and could trigger the
        # entitlement gate. After the fix, 7d+1s is well below the 14d
        # ceiling and goes through cleanly.
        ttl = 604_800 + 1
        logic = create_logic(logic_class, params: conceal_params(ttl), org: org)
        expect { logic.process_params }.not_to raise_error
        expect(logic.ttl).to eq(ttl)
      end

      it 'still rejects a TTL of 14 days + 1 second (new boundary enforced)' do
        ttl = (14 * 24 * 60 * 60) + 1
        # process_params runs in constructor, so error is raised during create_logic
        expect {
          create_logic(logic_class, params: conceal_params(ttl), org: org)
        }.to raise_error(Onetime::EntitlementRequired)
      end

      it 'FREE_TTL constant resolves to 14 days' do
        # Guards against future regressions where someone reverts the
        # constant; this spec relies on FREE_TTL pointing at 14 days.
        expect(FREE_TTL).to eq(14 * 24 * 60 * 60)
        expect(FREE_TTL).to eq(1_209_600)
      end
    end
  end

  describe V2::Logic::Secrets::ConcealSecret do
    include_examples 'extended_default_expiration TTL gate', -> { V2::Logic::Secrets::ConcealSecret }
  end

  describe V2::Logic::Secrets::GenerateSecret do
    include_examples 'extended_default_expiration TTL gate', -> { V2::Logic::Secrets::GenerateSecret }
  end
end
