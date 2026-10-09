# apps/web/auth/spec/operations/join_domain_organization_spec.rb
#
# frozen_string_literal: true

# The SSO self-heal picks the personal workspace it archives from the
# customer's OWN default workspace. On the shared lookup fixture (another
# owner's default listed first, the customer's archived default second, their
# live owned default third) the old implicit scan stopped at the first
# is_default flag — the foreign one — and then gave up, so the customer kept
# landing in their stale personal workspace. The integration coverage for the
# full join flow is apps/web/auth/spec/integration/full/domain_sso_join_organization_spec.rb.
#
# Run: tests/lanes/run unit --only apps/web/auth/spec/operations/join_domain_organization_spec.rb
require 'spec_helper'
require 'auth/operations/join_domain_organization'

RSpec.describe Auth::Operations::JoinDomainOrganization do
  subject(:result) { described_class.new(customer: customer, domain_id: 'dom_1').call }

  include_context 'default workspace lookup fixture'

  let(:default_org_id) { '' }
  let(:memberships) { lookup_fixture_orgs }
  let(:customer) do
    double(
      'Customer',
      custid: 'cust_sso',
      objid: 'cust_sso',
      anonymous?: false,
      organization_instances: memberships,
      save: true,
    ).tap do |c|
      allow(c).to receive(:default_org_id).and_return(default_org_id)
      allow(c).to receive(:default_org_id=)
    end
  end

  let(:domain_org) do
    instance_double(
      Onetime::Organization,
      objid: 'org-domain',
      extid: 'or_domain',
      display_name: 'Company',
      is_default: false,
      archived?: false,
    )
  end
  let(:domain) { double('CustomDomain', objid: 'dom_1', identifier: 'dom_1', display_domain: 'secrets.example.com', primary_organization: domain_org) }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:le)
    allow(Onetime::CustomDomain).to receive(:find_by_identifier).with('dom_1').and_return(domain)
    # already_member path: the self-heal retry runs without a new membership write.
    allow(domain_org).to receive(:member?).with(customer).and_return(true)
    stub_workspace_ownership(customer)
    lookup_fixture_orgs.each { |org| allow(org).to receive(:archive!) }
    allow(Onetime::Organization).to receive(:load) { |id| lookup_fixture_orgs.find { |o| o.objid == id } }
  end

  context 'with no explicit preference (implicit fallback)' do
    it 'adopts the domain org and archives the owned default, not the foreign one listed first' do
      expect(result[:reason]).to eq('already_member')
      expect(result[:adoption]).to include(adopted: true, archived_org_id: owned_default.objid)
      expect(customer).to have_received(:default_org_id=).with(domain_org.objid)
      expect(customer).to have_received(:save)
      expect(owned_default).to have_received(:archive!)
      expect(foreign_default).not_to have_received(:archive!)
      expect(archived_default).not_to have_received(:archive!)
    end

    context 'when the customer owns no live default workspace' do
      let(:memberships) { [foreign_default, archived_default] }

      it 'adopts nothing and archives nothing' do
        expect(result[:adoption]).to be_nil
        expect(customer).not_to have_received(:default_org_id=)
        expect(foreign_default).not_to have_received(:archive!)
      end
    end
  end

  context 'with an explicit preference naming a joined organization' do
    let(:default_org_id) { foreign_default.objid }

    it 'leaves the preference alone instead of replacing it with the owned default' do
      expect(result[:adoption]).to be_nil
      expect(customer).not_to have_received(:default_org_id=)
      expect(owned_default).not_to have_received(:archive!)
      expect(foreign_default).not_to have_received(:archive!)
    end
  end

  context 'with an explicit preference naming the owned default' do
    let(:default_org_id) { owned_default.objid }

    it 'adopts through the explicit path' do
      expect(result[:adoption]).to include(adopted: true, archived_org_id: owned_default.objid)
      expect(owned_default).to have_received(:archive!)
    end
  end
end
