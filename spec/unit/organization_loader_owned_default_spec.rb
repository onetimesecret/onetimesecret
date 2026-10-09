# spec/unit/organization_loader_owned_default_spec.rb
#
# frozen_string_literal: true

# The two default-workspace resolvers side by side, on the shared lookup
# fixture (another owner's default first, the customer's archived default
# second, the customer's live owned default third):
#
#   default_organization       — where the user lands. Follows an explicit
#                                default_org_id to any live membership;
#                                otherwise the is_default workspace they own.
#   owned_default_organization — the workspace operations may act on. Both
#                                steps are restricted to organizations the
#                                customer owns; a preference naming a joined
#                                organization is ignored, not followed.
#
# Run: tests/lanes/run unit --only spec/unit/organization_loader_owned_default_spec.rb
require 'spec_helper'
require 'onetime/application/organization_loader'

RSpec.describe Onetime::Application::OrganizationLoader do
  include_context 'default workspace lookup fixture'

  let(:default_org_id) { '' }
  let(:memberships) { lookup_fixture_orgs }
  let(:customer) do
    double(
      'customer',
      objid: 'cust_lookup',
      anonymous?: false,
      default_org_id: default_org_id,
      organization_instances: memberships,
    )
  end

  # A second live organization the customer owns, not flagged as default.
  let(:owned_team) do
    instance_double(
      Onetime::Organization,
      objid: 'org-owned-team',
      extid: 'or_owned_team',
      display_name: 'Team',
      is_default: false,
      archived?: false,
    )
  end

  before do
    stub_workspace_ownership(customer)
    allow(owned_team).to receive(:owner?).with(customer).and_return(true)
  end

  describe '.owned_default_organization' do
    it 'selects the owned live default past a foreign default listed first and an archived own default' do
      expect(described_class.owned_default_organization(customer)).to be(owned_default)
    end

    it 'does not depend on membership order' do
      expect(described_class.owned_default_organization(customer, lookup_fixture_orgs.reverse)).to be(owned_default)
    end

    context 'when default_org_id names a workspace the customer owns' do
      let(:default_org_id) { owned_team.objid }
      let(:memberships) { lookup_fixture_orgs + [owned_team] }

      it 'honours the preference' do
        expect(described_class.owned_default_organization(customer)).to be(owned_team)
      end
    end

    context 'when default_org_id names a joined organization' do
      let(:default_org_id) { foreign_default.objid }

      it 'ignores the preference and selects the owned default' do
        expect(described_class.owned_default_organization(customer)).to be(owned_default)
      end
    end

    context 'when default_org_id names the archived owned workspace' do
      let(:default_org_id) { archived_default.objid }

      it 'ignores the preference and selects the live owned default' do
        expect(described_class.owned_default_organization(customer)).to be(owned_default)
      end
    end

    context 'when the customer owns no live default workspace' do
      let(:memberships) { [foreign_default, archived_default, owned_team] }

      it 'returns nil rather than a joined or archived one' do
        expect(described_class.owned_default_organization(customer)).to be_nil
      end
    end

    it 'returns nil for no customer or an anonymous one' do
      anonymous = double('anonymous', anonymous?: true)

      expect(described_class.owned_default_organization(nil)).to be_nil
      expect(described_class.owned_default_organization(anonymous)).to be_nil
    end
  end

  describe '.owned_organizations' do
    let(:memberships) { lookup_fixture_orgs + [owned_team] }

    it 'lists only the live organizations the customer owns, in membership order' do
      expect(described_class.owned_organizations(customer)).to eq([owned_default, owned_team])
    end

    it 'is empty for no customer or an anonymous one' do
      expect(described_class.owned_organizations(nil)).to eq([])
      expect(described_class.owned_organizations(double('anonymous', anonymous?: true))).to eq([])
    end
  end

  describe '.default_organization (the user-default resolver, for contrast)' do
    it 'never reaches the foreign default through the is_default flag' do
      expect(described_class.default_organization(customer)).to be(owned_default)
    end

    context 'when default_org_id names a joined organization' do
      let(:default_org_id) { foreign_default.objid }

      it 'follows the explicit preference there' do
        expect(described_class.default_organization(customer)).to be(foreign_default)
      end
    end
  end
end
