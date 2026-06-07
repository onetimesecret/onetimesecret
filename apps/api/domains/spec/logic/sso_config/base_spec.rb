# apps/api/domains/spec/logic/sso_config/base_spec.rb
#
# frozen_string_literal: true

# Unit tests for SsoConfig::Base authorization logic.
#
# Authorization errors are raised via the DomainConfigAuthorization
# policy using raise_form_error (FormError with error_type: :forbidden)
# for feature flag and entitlement checks, and Onetime::Forbidden for
# organization ownership checks (via verify_one_of_roles!).
#
# RUN:
#   pnpm run test:rspec apps/api/domains/spec/logic/sso_config/base_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe DomainsAPI::Logic::SsoConfig::Base do
  # Test through a concrete subclass since Base is abstract
  let(:described_logic_class) { DomainsAPI::Logic::SsoConfig::GetSsoConfig }

  let(:owner) do
    instance_double(
      Onetime::Customer,
      custid: 'owner123',
      objid: 'owner123',
      extid: 'ext-owner123',
      anonymous?: false,
      verified?: true,
    )
  end

  let(:non_owner) do
    instance_double(
      Onetime::Customer,
      custid: 'nonowner123',
      objid: 'nonowner123',
      extid: 'ext-nonowner123',
      anonymous?: false,
      verified?: true,
    )
  end

  let(:organization) do
    instance_double(
      Onetime::Organization,
      objid: 'org123',
      extid: 'ext-org123',
      display_name: 'Test Org',
    )
  end

  let(:custom_domain) do
    instance_double(
      Onetime::CustomDomain,
      identifier: 'domain123',
      extid: 'ext-domain123',
      display_domain: 'example.com',
      org_id: 'org123',
    )
  end

  let(:session) do
    {
      'authenticated' => true,
      'csrf' => 'test-csrf-token',
    }
  end

  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: owner,
      authenticated?: true,
      metadata: {},
    )
  end

  let(:params) { { 'domain_id' => 'ext-domain123' } }
  let(:logic) { described_logic_class.new(strategy_result, params) }

  # ADR-012 Stage 4: membership with entitlements for authorization
  let(:owner_membership) do
    instance_double(
      Onetime::OrganizationMembership,
      active?: true,
      can?: true  # Default: has all entitlements (owner-level)
    )
  end

  let(:non_owner_membership) do
    instance_double(
      Onetime::OrganizationMembership,
      active?: true,
      can?: false  # Member without owner-level entitlements
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(OT).to receive(:now).and_return(Time.now.to_i)

    # Default: stub membership lookup for owner
    allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
      .with('org123', 'owner123')
      .and_return(owner_membership)
  end

  describe 'policy integration' do
    it 'includes DomainConfigAuthorization policy' do
      expect(described_class).to be < DomainsAPI::Policies::DomainConfigAuthorization
    end

    it 'includes AuthorizationPolicies via the policy' do
      expect(described_class).to be < Onetime::Application::AuthorizationPolicies
    end

    it 'returns manage_sso as config_entitlement' do
      expect(logic.send(:config_entitlement)).to eq('manage_sso')
    end

    it 'returns sso_enabled as config_feature_flag' do
      expect(logic.send(:config_feature_flag)).to eq('sso_enabled')
    end

    it 'returns SsoConfig as config_log_tag' do
      expect(logic.send(:config_log_tag)).to eq('SsoConfig')
    end
  end

  describe '#authorize_domain_sso!' do
    context 'when ORGS_SSO_ENABLED feature flag is false' do
      before do
        allow(OT).to receive(:conf).and_return({
          'features' => { 'organizations' => { 'sso_enabled' => false } },
        })
      end

      it 'raises forbidden error' do
        expect {
          logic.send(:authorize_domain_sso!, 'ext-domain123')
        }.to raise_error(Onetime::FormError) do |error|
          expect(error.message).to eq('Organization SSO is not enabled on this instance')
          expect(error.error_type).to eq(:forbidden)
        end
      end

      it 'logs feature flag denial with structured info' do
        logic.send(:authorize_domain_sso!, 'ext-domain123') rescue nil
        expect(OT).to have_received(:info).with(
          a_string_matching(/\[SsoConfig\] Authorization denied: sso_enabled feature flag disabled/),
          anything,
        )
      end
    end

    context 'when ORGS_SSO_ENABLED feature flag is nil/missing' do
      before do
        allow(OT).to receive(:conf).and_return({
          'features' => { 'organizations' => {} },
        })
      end

      it 'raises forbidden error' do
        expect {
          logic.send(:authorize_domain_sso!, 'ext-domain123')
        }.to raise_error(Onetime::FormError) do |error|
          expect(error.message).to eq('Organization SSO is not enabled on this instance')
          expect(error.error_type).to eq(:forbidden)
        end
      end
    end

    context 'when features.organizations is completely missing' do
      before do
        allow(OT).to receive(:conf).and_return({
          'features' => {},
        })
      end

      it 'raises forbidden error' do
        expect {
          logic.send(:authorize_domain_sso!, 'ext-domain123')
        }.to raise_error(Onetime::FormError) do |error|
          expect(error.message).to eq('Organization SSO is not enabled on this instance')
        end
      end
    end

    context 'when ORGS_SSO_ENABLED is true but domain not found' do
      before do
        allow(OT).to receive(:conf).and_return({
          'features' => { 'organizations' => { 'sso_enabled' => true } },
        })
        allow(Onetime::CustomDomain).to receive(:find_by_extid).with('nonexistent').and_return(nil)
      end

      it 'raises not_found error' do
        expect {
          logic.send(:authorize_domain_sso!, 'nonexistent')
        }.to raise_error(Onetime::RecordNotFound)
      end
    end

    context 'when user lacks manage_org entitlement' do
      let(:non_owner_strategy_result) do
        double('StrategyResult',
          session: session,
          user: non_owner,
          authenticated?: true,
          metadata: {},
        )
      end
      let(:logic) { described_logic_class.new(non_owner_strategy_result, params) }

      before do
        allow(OT).to receive(:conf).and_return({
          'features' => { 'organizations' => { 'sso_enabled' => true } },
        })
        allow(Onetime::CustomDomain).to receive(:find_by_extid)
          .with('ext-domain123').and_return(custom_domain)
        allow(Onetime::Organization).to receive(:load)
          .with('org123').and_return(organization)
        allow(organization).to receive(:owner?).with(non_owner).and_return(false)
        allow(logic).to receive(:cust).and_return(non_owner)
        # Colonel check - user is not a colonel
        allow(non_owner).to receive(:role).and_return('customer')
        # ADR-012 Stage 4: membership without manage_org entitlement
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
          .with('org123', 'nonowner123')
          .and_return(non_owner_membership)
        allow(organization).to receive(:planid).and_return('basic')
      end

      it 'raises EntitlementRequired for user without manage_org entitlement' do
        expect {
          logic.send(:authorize_domain_sso!, 'ext-domain123')
        }.to raise_error(Onetime::EntitlementRequired) do |error|
          expect(error.entitlement).to eq('manage_org')
        end
      end
    end

    context 'when organization lacks manage_sso entitlement' do
      before do
        allow(OT).to receive(:conf).and_return({
          'features' => { 'organizations' => { 'sso_enabled' => true } },
        })
        allow(Onetime::CustomDomain).to receive(:find_by_extid)
          .with('ext-domain123').and_return(custom_domain)
        allow(Onetime::Organization).to receive(:load)
          .with('org123').and_return(organization)
        allow(organization).to receive(:owner?).with(owner).and_return(true)
        # Org lacks manage_sso entitlement (checked by verify_config_entitlement)
        allow(organization).to receive(:can?).with('manage_sso').and_return(false)
        allow(logic).to receive(:cust).and_return(owner)
        allow(owner).to receive(:role).and_return('customer')
        # ADR-012 Stage 4: owner has manage_org (passes require_entitlement_in!)
        # but org lacks manage_sso (fails verify_config_entitlement)
      end

      it 'raises forbidden error for missing entitlement' do
        expect {
          logic.send(:authorize_domain_sso!, 'ext-domain123')
        }.to raise_error(Onetime::FormError) do |error|
          expect(error.message).to include('manage_sso')
          expect(error.error_type).to eq(:forbidden)
        end
      end

      it 'logs entitlement denial with structured info' do
        logic.send(:authorize_domain_sso!, 'ext-domain123') rescue nil
        expect(OT).to have_received(:info).with(
          a_string_matching(/\[SsoConfig\] Authorization denied: missing manage_sso entitlement/),
          anything,
        )
      end
    end

    context 'when all authorization checks pass' do
      before do
        allow(OT).to receive(:conf).and_return({
          'features' => { 'organizations' => { 'sso_enabled' => true } },
        })
        allow(Onetime::CustomDomain).to receive(:find_by_extid)
          .with('ext-domain123').and_return(custom_domain)
        allow(Onetime::Organization).to receive(:load)
          .with('org123').and_return(organization)
        allow(organization).to receive(:owner?).with(owner).and_return(true)
        allow(organization).to receive(:can?).with('manage_sso').and_return(true)
        allow(logic).to receive(:cust).and_return(owner)
        allow(owner).to receive(:role).and_return('customer')
      end

      it 'does not raise an error' do
        expect {
          logic.send(:authorize_domain_sso!, 'ext-domain123')
        }.not_to raise_error
      end

      it 'sets @custom_domain' do
        logic.send(:authorize_domain_sso!, 'ext-domain123')
        expect(logic.instance_variable_get(:@custom_domain)).to eq(custom_domain)
      end

      it 'sets @organization' do
        logic.send(:authorize_domain_sso!, 'ext-domain123')
        expect(logic.instance_variable_get(:@organization)).to eq(organization)
      end

      it 'logs authorization granted via structured debug log' do
        logic.send(:authorize_domain_sso!, 'ext-domain123')
        expect(OT).to have_received(:ld).with(
          a_string_matching(/\[SsoConfig\] Authorization granted/),
        )
      end
    end

    context 'when user is a colonel (site admin)' do
      before do
        allow(OT).to receive(:conf).and_return({
          'features' => { 'organizations' => { 'sso_enabled' => true } },
        })
        allow(Onetime::CustomDomain).to receive(:find_by_extid)
          .with('ext-domain123').and_return(custom_domain)
        allow(Onetime::Organization).to receive(:load)
          .with('org123').and_return(organization)
        # User is NOT the owner but IS a colonel
        allow(organization).to receive(:owner?).with(owner).and_return(false)
        allow(organization).to receive(:can?).with('manage_sso').and_return(true)
        allow(logic).to receive(:cust).and_return(owner)
        allow(owner).to receive(:role).and_return('colonel')
      end

      it 'allows access due to colonel bypass' do
        expect {
          logic.send(:authorize_domain_sso!, 'ext-domain123')
        }.not_to raise_error
      end
    end
  end
end
