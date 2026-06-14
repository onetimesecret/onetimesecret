# apps/api/domains/spec/logic/domains/get_domain_image_spec.rb
#
# frozen_string_literal: true

# Unit tests for GetDomainImage read-only authorization logic.
#
# GetDomainImage (and its subclasses GetDomainLogo, GetDomainIcon)
# includes DomainConfigAuthorization but intentionally skips
# authorize_domain_config! — it calls load_custom_domain,
# load_organization_for_domain, and require_entitlement_in! directly
# so regular org members (without manage_org) can view image data
# and the UI can render the brand page as a disabled overlay.
#
# RUN:
#   pnpm run test:rspec apps/api/domains/spec/logic/domains/get_domain_image_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe DomainsAPI::Logic::Domains::GetDomainImage do
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

  let(:member) do
    instance_double(
      Onetime::Customer,
      custid: 'member123',
      objid: 'member123',
      extid: 'ext-member123',
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

  let(:logo_field) do
    double('LogoField',
      '[]' => nil,
      'key?' => true,
      hgetall: { 'encoded' => 'base64data', 'filename' => 'logo.png', 'content_type' => 'image/png' },
    )
  end

  let(:empty_logo_field) do
    double('EmptyLogoField',
      '[]' => nil,
      'key?' => false,
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

  let(:owner_strategy_result) do
    double('StrategyResult',
      session: session,
      user: owner,
      authenticated?: true,
      metadata: {},
    )
  end

  let(:member_strategy_result) do
    double('StrategyResult',
      session: session,
      user: member,
      authenticated?: true,
      metadata: {},
    )
  end

  let(:params) { { 'extid' => 'abc123' } }

  let(:owner_membership) do
    instance_double(
      Onetime::OrganizationMembership,
      active?: true,
      can?: true,
    )
  end

  let(:member_membership) do
    instance_double(
      Onetime::OrganizationMembership,
      active?: true,
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(OT).to receive(:now).and_return(Time.now.to_i)

    allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
      .with('org123', 'owner123')
      .and_return(owner_membership)

    # Domain-scope enforcement (#3384): memberships must respond to can_access_domain?
    allow(owner_membership).to receive(:can_access_domain?).and_return(true)
    allow(member_membership).to receive(:can_access_domain?).and_return(true)
  end

  describe DomainsAPI::Logic::Domains::GetDomainLogo do
    let(:logic) { described_class.new(owner_strategy_result, params) }

    describe 'policy integration' do
      it 'includes DomainConfigAuthorization policy' do
        expect(described_class).to be < DomainsAPI::Policies::DomainConfigAuthorization
      end

      it 'includes AuthorizationPolicies via the policy' do
        expect(described_class).to be < Onetime::Application::AuthorizationPolicies
      end

      it 'returns custom_branding as config_entitlement' do
        expect(logic.send(:config_entitlement)).to eq('custom_branding')
      end

      it 'uses :logo as the image field' do
        expect(described_class.field).to eq(:logo)
      end
    end

    describe '#raise_concerns (read-only authorization)' do
      context 'when extid is empty' do
        let(:params) { { 'extid' => '' } }

        it 'raises FormError' do
          logic.process_params
          expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /domain ID/)
        end
      end

      context 'when extid has invalid format' do
        let(:params) { { 'extid' => 'ABC-123!' } }

        it 'raises FormError for invalid identifier format' do
          logic.process_params
          expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Invalid domain identifier/)
        end
      end

      context 'when domain not found' do
        let(:params) { { 'extid' => 'nonexistent' } }

        before do
          allow(Onetime::CustomDomain).to receive(:find_by_extid).with('nonexistent').and_return(nil)
        end

        it 'raises RecordNotFound' do
          logic.process_params
          expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound)
        end
      end

      context 'when organization not found' do
        before do
          allow(Onetime::CustomDomain).to receive(:find_by_extid).with('abc123').and_return(custom_domain)
          allow(Onetime::Organization).to receive(:load).with('org123').and_return(nil)
        end

        it 'raises RecordNotFound' do
          logic.process_params
          expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound)
        end
      end

      context 'when user is not a member of the organization' do
        let(:outsider) do
          instance_double(
            Onetime::Customer,
            custid: 'outsider123',
            objid: 'outsider123',
            extid: 'ext-outsider123',
            anonymous?: false,
            verified?: true,
          )
        end

        let(:outsider_strategy_result) do
          double('StrategyResult',
            session: session,
            user: outsider,
            authenticated?: true,
            metadata: {},
          )
        end

        let(:logic) { described_class.new(outsider_strategy_result, params) }

        before do
          allow(Onetime::CustomDomain).to receive(:find_by_extid).with('abc123').and_return(custom_domain)
          allow(Onetime::Organization).to receive(:load).with('org123').and_return(organization)
          allow(outsider).to receive(:role).and_return('customer')
          allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
            .with('org123', 'outsider123')
            .and_return(nil)
        end

        it 'raises Forbidden' do
          logic.process_params
          expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
        end
      end

      context 'when member lacks custom_branding entitlement' do
        let(:logic) { described_class.new(member_strategy_result, params) }

        before do
          allow(Onetime::CustomDomain).to receive(:find_by_extid).with('abc123').and_return(custom_domain)
          allow(Onetime::Organization).to receive(:load).with('org123').and_return(organization)
          allow(member).to receive(:role).and_return('customer')
          allow(member_membership).to receive(:can?).with('custom_branding').and_return(false)
          allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
            .with('org123', 'member123')
            .and_return(member_membership)
          allow(organization).to receive(:planid).and_return('basic')
        end

        it 'raises EntitlementRequired for custom_branding' do
          logic.process_params
          expect { logic.raise_concerns }.to raise_error(Onetime::EntitlementRequired) do |error|
            expect(error.entitlement).to eq('custom_branding')
          end
        end
      end

      context 'when regular member has custom_branding (no manage_org needed)' do
        let(:logic) { described_class.new(member_strategy_result, params) }

        before do
          allow(Onetime::CustomDomain).to receive(:find_by_extid).with('abc123').and_return(custom_domain)
          allow(Onetime::Organization).to receive(:load).with('org123').and_return(organization)
          allow(member).to receive(:role).and_return('customer')
          allow(member_membership).to receive(:can?).with('custom_branding').and_return(true)
          allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
            .with('org123', 'member123')
            .and_return(member_membership)
          allow(custom_domain).to receive(:logo).and_return(logo_field)
          allow(logo_field).to receive(:[]).with('encoded').and_return('base64data')
        end

        it 'does not raise an error' do
          logic.process_params
          expect { logic.raise_concerns }.not_to raise_error
        end

        it 'sets @custom_domain' do
          logic.process_params
          logic.raise_concerns
          expect(logic.instance_variable_get(:@custom_domain)).to eq(custom_domain)
        end

        it 'sets @organization' do
          logic.process_params
          logic.raise_concerns
          expect(logic.instance_variable_get(:@organization)).to eq(organization)
        end
      end

      context 'when no image is stored' do
        before do
          allow(Onetime::CustomDomain).to receive(:find_by_extid).with('abc123').and_return(custom_domain)
          allow(Onetime::Organization).to receive(:load).with('org123').and_return(organization)
          allow(owner).to receive(:role).and_return('customer')
          allow(custom_domain).to receive(:logo).and_return(empty_logo_field)
          allow(empty_logo_field).to receive(:[]).with('encoded').and_return(nil)
        end

        it 'raises RecordNotFound for missing image' do
          logic.process_params
          expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound)
        end
      end

      context 'when user is a colonel (site admin)' do
        before do
          allow(Onetime::CustomDomain).to receive(:find_by_extid).with('abc123').and_return(custom_domain)
          allow(Onetime::Organization).to receive(:load).with('org123').and_return(organization)
          allow(owner).to receive(:role).and_return('colonel')
          allow(custom_domain).to receive(:logo).and_return(logo_field)
          allow(logo_field).to receive(:[]).with('encoded').and_return('base64data')
        end

        it 'allows access due to colonel bypass' do
          logic.process_params
          expect { logic.raise_concerns }.not_to raise_error
        end
      end
    end
  end

  describe DomainsAPI::Logic::Domains::GetDomainIcon do
    let(:icon_field) do
      double('IconField',
        '[]' => nil,
        'key?' => true,
        hgetall: { 'encoded' => 'base64data', 'filename' => 'icon.png', 'content_type' => 'image/png' },
      )
    end

    let(:logic) { described_class.new(owner_strategy_result, params) }

    it 'uses :icon as the image field' do
      expect(described_class.field).to eq(:icon)
    end

    context 'when regular member has custom_branding (no manage_org needed)' do
      let(:logic) { described_class.new(member_strategy_result, params) }

      before do
        allow(Onetime::CustomDomain).to receive(:find_by_extid).with('abc123').and_return(custom_domain)
        allow(Onetime::Organization).to receive(:load).with('org123').and_return(organization)
        allow(member).to receive(:role).and_return('customer')
        allow(member_membership).to receive(:can?).with('custom_branding').and_return(true)
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
          .with('org123', 'member123')
          .and_return(member_membership)
        allow(custom_domain).to receive(:icon).and_return(icon_field)
        allow(icon_field).to receive(:[]).with('encoded').and_return('base64data')
      end

      it 'does not raise an error' do
        logic.process_params
        expect { logic.raise_concerns }.not_to raise_error
      end
    end
  end
end
