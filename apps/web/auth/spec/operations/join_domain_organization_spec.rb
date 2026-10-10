# apps/web/auth/spec/operations/join_domain_organization_spec.rb
#
# frozen_string_literal: true

# The SSO self-heal repoints default_org_id from the customer's OWN default
# workspace to the domain org. On the shared lookup fixture (another owner's
# default listed first, the customer's archived default second, their live
# owned default third) the old implicit scan stopped at the first is_default
# flag — the foreign one — and then gave up, so the customer kept landing in
# their stale personal workspace.
#
# #4717 PR 2: login never archives. Joining an organization and choosing a
# default are the login path's two decisions; retiring a workspace is an
# operator decision (Onetime::Operations::Org::Delete / Unarchive). Every
# `archive!` stub here RAISES, so a stray call from the login path is a loud
# failure (the op rescues it into `adoption: nil`, which the adopting examples
# then reject). The integration coverage for the full join flow is
# apps/web/auth/spec/integration/full/domain_sso_join_organization_spec.rb.
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
    forbid_archive(*lookup_fixture_orgs)
    allow(Onetime::Organization).to receive(:load) { |id| lookup_fixture_orgs.find { |o| o.objid == id } }
  end

  # Recorded AND fatal: the spy lets an example name the offender, and the
  # raise makes sure no path quietly archives on the way to a green result.
  def forbid_archive(*orgs)
    orgs.each do |org|
      allow(org).to receive(:archive!).and_raise(RuntimeError, 'the login path must never archive an organization')
    end
  end

  # The PR 2 adoption contract: a pointer-only repoint, nothing archived.
  def expect_pointer_only_adoption(previous:)
    expect(result[:reason]).to eq('already_member')
    lookup_fixture_orgs.each { |org| expect(org).not_to have_received(:archive!) }
    expect(result[:adoption]).to include(adopted: true, previous_default_org_id: previous.objid)
    expect(result[:adoption]).not_to have_key(:archived_org_id)
    expect(customer).to have_received(:default_org_id=).with(domain_org.objid)
    expect(customer).to have_received(:save)
  end

  context 'with no explicit preference (implicit fallback)' do
    it 'repoints to the domain org from the owned default (not the foreign one listed first) and archives nothing' do
      expect_pointer_only_adoption(previous: owned_default)
    end

    context 'when the customer owns no live default workspace' do
      let(:memberships) { [foreign_default, archived_default] }

      it 'adopts nothing and writes nothing' do
        expect(result[:adoption]).to be_nil
        expect(customer).not_to have_received(:default_org_id=)
        expect(customer).not_to have_received(:save)
        expect(foreign_default).not_to have_received(:archive!)
      end
    end
  end

  context 'with an explicit preference naming a joined organization' do
    let(:default_org_id) { foreign_default.objid }

    it 'leaves the preference alone instead of replacing it with the owned default' do
      expect(result[:adoption]).to be_nil
      expect(customer).not_to have_received(:default_org_id=)
      expect(customer).not_to have_received(:save)
      expect(owned_default).not_to have_received(:archive!)
      expect(foreign_default).not_to have_received(:archive!)
    end
  end

  # The already_member path is the only path this file exercises (member? is
  # stubbed true), so this IS the retry: a customer who joined earlier but is
  # still pointed at their own default workspace gets repointed on the next
  # login, with the workspace left live (decision D1, #4717).
  context 'with an explicit preference naming the owned default (already-member retry)' do
    let(:default_org_id) { owned_default.objid }

    it 'repoints through the explicit path and archives nothing' do
      expect_pointer_only_adoption(previous: owned_default)
    end
  end

  # #4717 — the destination is never the candidate. When the signed-in
  # customer OWNS the domain org and that org carries is_default: true (the
  # owner's auto-created workspace later promoted to a tenant org), both
  # resolution paths hand adopt_domain_default_org the domain org itself:
  # the explicit pointer names it, and the implicit owned-default lookup
  # selects it. Nothing compared the candidate to the destination, so the
  # owner's own tenant org was archived on every tenant SSO login (the
  # already_member path retries adoption). The self-heal must return before
  # any write when candidate and destination are the same organization —
  # compared by objid, because Organization.load hands back a fresh
  # instance, never the object the domain returned.
  context 'when the owned default workspace IS the domain org (#4717)' do
    let(:domain_org) do
      instance_double(
        Onetime::Organization,
        objid: 'org-domain',
        extid: 'or_domain',
        display_name: 'Company',
        is_default: true,
        archived?: false,
      )
    end

    before do
      allow(domain_org).to receive(:owner?).with(customer).and_return(true)
      forbid_archive(domain_org)
      allow(Onetime::Organization).to receive(:load) do |id|
        (lookup_fixture_orgs + [domain_org]).find { |o| o.objid == id }
      end
    end

    shared_examples 'leaves the domain org and the pointer alone' do
      it 'adopts nothing and never archives the destination' do
        expect(result[:reason]).to eq('already_member')
        expect(domain_org).not_to have_received(:archive!)
        lookup_fixture_orgs.each { |org| expect(org).not_to have_received(:archive!) }
        expect(result).not_to have_key(:adoption)
        expect(customer).not_to have_received(:default_org_id=)
        expect(customer).not_to have_received(:save)
      end
    end

    # Pointer already at the destination: the already_member retry has
    # nothing to repoint, so it performs no write at all.
    context 'with the explicit pointer already at the domain org' do
      let(:default_org_id) { domain_org.objid }

      include_examples 'leaves the domain org and the pointer alone'
    end

    context 'with no explicit pointer and the domain org as the only owned live default' do
      let(:default_org_id) { '' }
      # Foreign default first (the fixture's ordering trap), the customer's
      # archived former default second, the domain org third: the owned-default
      # lookup selects the domain org, exactly as OrganizationLoader step 4 would.
      let(:memberships) { [foreign_default, archived_default, domain_org] }

      include_examples 'leaves the domain org and the pointer alone'
    end

    context 'when Organization.load returns a different instance with the same objid' do
      let(:default_org_id) { domain_org.objid }
      let(:domain_org_twin) do
        instance_double(
          Onetime::Organization,
          objid: domain_org.objid,
          extid: domain_org.extid,
          display_name: 'Company (reloaded)',
          is_default: true,
          archived?: false,
        )
      end

      before do
        allow(domain_org_twin).to receive(:owner?).with(customer).and_return(true)
        forbid_archive(domain_org_twin)
        allow(Onetime::Organization).to receive(:load).with(domain_org.objid).and_return(domain_org_twin)
      end

      # Pins "compare objid, not identity": `personal_org.equal?(domain_org)`
      # would be false here and the twin would be archived.
      it 'recognises the destination by objid and archives neither instance' do
        expect(result[:reason]).to eq('already_member')
        expect(domain_org_twin).not_to have_received(:archive!)
        expect(domain_org).not_to have_received(:archive!)
        expect(result).not_to have_key(:adoption)
        expect(customer).not_to have_received(:default_org_id=)
        expect(customer).not_to have_received(:save)
      end
    end
  end
end
