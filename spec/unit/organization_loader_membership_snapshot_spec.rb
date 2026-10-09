# spec/unit/organization_loader_membership_snapshot_spec.rb
#
# frozen_string_literal: true

# One request reads a customer's memberships once. The auth-phase load, the
# default lookups the API payloads and the bootstrap serializer make, and
# the owned-workspace lookups all answer from the request's
# Onetime::MembershipSnapshot. The user's default over all memberships is
# resolved once; the selection filtered by the request's domain scope is
# computed from the same list and never stands in for it.
#
# Run: tests/lanes/run unit --only spec/unit/organization_loader_membership_snapshot_spec.rb
require 'spec_helper'
require 'onetime/application/organization_loader'

RSpec.describe Onetime::Application::OrganizationLoader do
  include_context 'default workspace lookup fixture'

  let(:loader) { described_class }
  let(:default_org_id) { '' }
  let(:customer) do
    double(
      'customer',
      objid: 'cust_snapshot',
      anonymous?: false,
      default_org_id: default_org_id,
      organization_instances: lookup_fixture_orgs,
    )
  end

  before do
    stub_workspace_ownership(customer)
    Onetime::MembershipSnapshot.open
  end

  after { Onetime::MembershipSnapshot.close }

  describe 'within one request' do
    it 'reads the membership list once across the load and the default lookups' do
      expect(customer).to receive(:organization_instances).once.and_return(lookup_fixture_orgs)

      context = loader.load_organization_context(customer, {}, {})

      expect(context[:organization]).to be(owned_default)
      expect(loader.default_organization(customer)).to be(owned_default)
      expect(loader.default_organization(customer)).to be(owned_default)
      expect(loader.owned_default_organization(customer)).to be(owned_default)
      expect(loader.owned_organizations(customer)).to eq([owned_default])
    end

    it 'reads each ownership once' do
      expect(foreign_default).to receive(:owner?).with(customer).once.and_return(false)
      expect(owned_default).to receive(:owner?).with(customer).once.and_return(true)

      loader.load_organization_context(customer, {}, {})
      loader.default_organization(customer)
      loader.owned_organizations(customer)
    end

    context 'when the preference names an organization the user merely belongs to' do
      let(:default_org_id) { foreign_default.objid }

      it 'resolves the user default once and does not read ownership for it' do
        expect(foreign_default).not_to receive(:owner?)

        expect(loader.load_organization_context(customer, {}, {})[:organization]).to be(foreign_default)
        expect(loader.default_organization(customer)).to be(foreign_default)
      end
    end
  end

  describe 'the domain-filtered selection' do
    let(:default_org_id) { foreign_default.objid }
    let(:domain) { instance_double(Onetime::CustomDomain, objid: 'domain-1') }
    let(:foreign_membership) { instance_double(Onetime::OrganizationMembership) }
    let(:owned_membership) { instance_double(Onetime::OrganizationMembership) }

    before do
      allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
        .with(foreign_default.objid, customer.objid).and_return(foreign_membership)
      allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
        .with(owned_default.objid, customer.objid).and_return(owned_membership)
      allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
        .with(archived_default.objid, customer.objid).and_return(nil)
      allow(foreign_membership).to receive(:can_access_domain?).with(domain).and_return(false)
      allow(owned_membership).to receive(:can_access_domain?).with(domain).and_return(true)
    end

    def select_on_domain
      loader.send(:determine_organization, customer, {}, nil, [domain])
    end

    it 'is computed from the snapshot but never replaces the user default' do
      expect(select_on_domain).to be(owned_default)
      expect(loader.default_organization(customer)).to be(foreign_default)
      expect(select_on_domain).to be(owned_default)
    end

    it 'reads each membership record once' do
      expect(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
        .with(owned_default.objid, customer.objid).once.and_return(owned_membership)

      select_on_domain
      select_on_domain
      loader.send(:scope_withheld_any?, customer, [domain])
    end
  end

  describe 'after the snapshot is forgotten' do
    it 'reads the membership list again' do
      expect(customer).to receive(:organization_instances).twice.and_return(lookup_fixture_orgs)

      loader.default_organization(customer)
      Onetime::MembershipSnapshot.forget(customer)
      loader.default_organization(customer)
    end
  end

  describe 'with no request store open' do
    before { Onetime::MembershipSnapshot.close }

    it 'reads the membership list on every lookup' do
      expect(customer).to receive(:organization_instances).twice.and_return(lookup_fixture_orgs)

      loader.default_organization(customer)
      loader.default_organization(customer)
    end
  end
end
