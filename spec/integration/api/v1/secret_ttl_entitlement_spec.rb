# spec/integration/api/v1/secret_ttl_entitlement_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Integration tests for API V1 TTL Entitlement Gate (#3074)
#
# V1's contract differs from V2/V3: the entitlement gate fires AFTER
# silent TTL clamping. So a request with `ttl=30 days` against a plan
# that caps `secret_lifetime` at 7 days clamps quietly to 7 days and
# never trips the gate. The gate only fires when the plan grants more
# than DEFAULT_FREE_TTL but the org lacks `extended_default_expiration`.
#
# This V1-specific behavior is preserved for v0.23.4 backward
# compatibility (#2621) and must be locked in independently of V2/V3.
#
RSpec.describe 'API V1 Secret TTL Entitlement Gate', type: :integration, billing: true do
  FREE_TTL = Onetime::Models::Features::WithEntitlements::DEFAULT_FREE_TTL

  def mock_organization(planid:, entitlements:, secret_lifetime: FREE_TTL)
    org = double('Organization', planid: planid, objid: "org_#{SecureRandom.hex(4)}")
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
    allow(customer).to receive(:organization_instances).and_return([])
    allow(customer).to receive(:is_a?).and_call_original
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

  # V1 logic constructors take (sess, cust, params, locale) — there is
  # no strategy_result and V1::Logic::Base doesn't include
  # OrganizationContext. We stub `auth_org` so the gate's
  # `respond_to?(:auth_org)` branch is taken.
  def create_logic(logic_class, params:, org:, customer: nil)
    customer ||= mock_customer(anonymous: org.nil?)
    session = mock_session

    # V1 calls process_params during initialize when params are present.
    # We need auth_org defined BEFORE that runs, so build the instance
    # without params and then inject params manually.
    logic = logic_class.allocate
    logic.instance_variable_set(:@sess, session)
    logic.instance_variable_set(:@cust, customer)
    logic.instance_variable_set(:@params, params)
    logic.instance_variable_set(:@locale, nil)
    logic.instance_variable_set(:@processed_params, {})
    allow(logic).to receive(:auth_org).and_return(org)
    logic.send(:process_settings)
    logic
  end

  def stub_secret_options
    allow(OT).to receive(:conf).and_return(
      'site' => {
        'secret_options' => {
          'default_ttl' => 7 * 24 * 60 * 60,
          'ttl_options' => [60, 3600, 86_400, 604_800, 2_592_000],
        },
        'domains' => { 'enabled' => false },
        'authentication' => {},
      },
    )
  end

  before(:all) do
    require 'onetime'
    Onetime.boot! :test
  end

  before { stub_secret_options }

  shared_examples 'V1 extended_default_expiration TTL gate' do |logic_class_proc|
    let(:logic_class) { logic_class_proc.call }

    def conceal_params(ttl)
      { 'secret' => 'test value', 'ttl' => ttl.to_s }
    end

    context 'when plan limit ≤ DEFAULT_FREE_TTL (clamp absorbs the request)' do
      let(:org) { mock_organization(planid: 'free_v1', entitlements: %w[create_secrets api_access], secret_lifetime: FREE_TTL) }

      it 'silently clamps a 30-day request to plan limit and does NOT raise (V1 contract)' do
        logic = create_logic(logic_class, params: conceal_params(2_592_000), org: org)
        expect { logic.process_params }.not_to raise_error
        expect(logic.ttl).to eq(FREE_TTL)
      end

      it 'silently clamps a request just above the boundary and does NOT raise' do
        logic = create_logic(logic_class, params: conceal_params(FREE_TTL + 60), org: org)
        expect { logic.process_params }.not_to raise_error
        expect(logic.ttl).to eq(FREE_TTL)
      end
    end

    context 'when plan limit > DEFAULT_FREE_TTL but org lacks the entitlement' do
      let(:org) { mock_organization(planid: 'identity', entitlements: %w[create_secrets api_access], secret_lifetime: 2_592_000) }

      it 'raises EntitlementRequired after clamp (clamped value still exceeds free_ttl)' do
        logic = create_logic(logic_class, params: conceal_params(2_592_000), org: org)
        expect { logic.process_params }.to raise_error(Onetime::EntitlementRequired) do |error|
          expect(error.entitlement).to eq('extended_default_expiration')
          expect(error.current_plan).to eq('identity')
        end
      end

      it 'raises even when the requested ttl exceeds plan_max (clamp first, then gate)' do
        logic = create_logic(logic_class, params: conceal_params(7_776_000), org: org)
        expect { logic.process_params }.to raise_error(Onetime::EntitlementRequired)
      end
    end

    context 'when plan limit > DEFAULT_FREE_TTL and org has the entitlement' do
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
    end

    context 'boundary: ttl == DEFAULT_FREE_TTL' do
      let(:org) { mock_organization(planid: 'identity', entitlements: %w[create_secrets api_access], secret_lifetime: 2_592_000) }

      it 'does not raise (gate uses >, not >=)' do
        logic = create_logic(logic_class, params: conceal_params(FREE_TTL), org: org)
        expect { logic.process_params }.not_to raise_error
        expect(logic.ttl).to eq(FREE_TTL)
      end
    end

    context 'when auth_org is nil' do
      it 'bypasses the gate (no auth_org → no entitlement check)' do
        logic = create_logic(logic_class, params: conceal_params(2_592_000), org: nil)
        expect { logic.process_params }.not_to raise_error
      end
    end
  end

  describe V1::Logic::Secrets::ConcealSecret do
    include_examples 'V1 extended_default_expiration TTL gate', -> { V1::Logic::Secrets::ConcealSecret }
  end

  describe V1::Logic::Secrets::GenerateSecret do
    include_examples 'V1 extended_default_expiration TTL gate', -> { V1::Logic::Secrets::GenerateSecret }
  end
end
