# apps/web/auth/spec/operations/customers/purge_preflight_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'auth/operations/customers/purge_preflight'

RSpec.describe Auth::Operations::Customers::PurgePreflight do
  let(:customer) do
    double(
      'Customer',
      objid: 'cust-target',
      extid: 'ur_target',
      custid: 'target@example.com',
      email: 'target@example.com',
      default_org_id: nil,
      dbkey: 'customer:cust-target:object',
      v1_custid: nil,
      migration_status: nil,
    )
  end
  let(:instances) { double('Organization.instances') }
  let(:membership_instances) { double('OrganizationMembership.instances') }
  let(:domain_instances) { double('CustomDomain.instances') }
  let(:contact_index) { double('Organization.contact_email_index') }

  before do
    allow(Onetime::Organization).to receive(:instances).and_return(instances)
    allow(Onetime::OrganizationMembership).to receive(:instances).and_return(membership_instances)
    allow(Onetime::CustomDomain).to receive(:instances).and_return(domain_instances)
    allow(Onetime::Organization).to receive(:load).and_return(nil)
    allow(Onetime::OrganizationMembership).to receive(:load).and_return(nil)
    allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer).and_return(nil)
    allow(Onetime::Organization).to receive(:contact_email_index).and_return(contact_index)
    allow(contact_index).to receive(:get).and_return(nil)
    # The index is keyed verbatim, so production resolves holders through these
    # two finders. Route them back at the `get` double each example stubs.
    allow(Onetime::Organization).to receive(:find_contact_email_claims) do |value, **_options|
      held = contact_index.get(value.to_s).to_s
      held.empty? ? {} : { value.to_s => held }
    end
    allow(Onetime::Organization).to receive(:find_contact_email_holder_id) do |value|
      contact_index.get(value.to_s)
    end
    # Shallow discovery probes registry membership for one id instead of reading
    # the whole registry.
    allow(instances).to receive(:member?).and_return(true)
    stub_instance_scan(instances, [])
    stub_instance_scan(membership_instances, [])
    stub_instance_scan(domain_instances, [])
    allow(customer).to receive(:participations).and_return(collection([]))
    allow(customer).to receive(:organization_instances).and_return(collection([]))
    allow(customer).to receive(:purge_pending_organization_checks).and_return(collection([]))
  end

  def organization(overrides = {})
    defaults = {
      objid: 'org-personal',
      extid: 'on_personal',
      owner_id: 'cust-target',
      created_by: 'cust-target',
      contact_email: 'target@example.com',
      is_default: 'true',
      domain_count: 0,
      unlisted_owned_domains: [],
      pending_invitation_count: 0,
      receipt_count: 0,
      billing_live?: false,
      subscription_status: nil,
      planid: 'free_v1',
      migration_status: nil,
      v1_identifier: nil,
      v1_source_custid: nil,
      members: collection(['cust-target']),
      pending_invitations: collection([]),
      domains: collection([]),
    }
    double('Organization', **defaults.merge(overrides))
  end

  def membership(org_objid:, customer_objid:, role:, status: 'active', objid: nil)
    objid ||= Onetime::OrganizationMembership.composite_objid(org_objid, customer_objid)
    double(
      'Membership',
      objid: objid,
      organization_objid: org_objid,
      customer_objid: customer_objid,
      role: role,
      active?: status == 'active',
      pending?: status == 'pending',
      owner?: role == 'owner',
    )
  end

  def collection(values)
    double('Collection', to_a: values)
  end

  def stub_instance_scan(registry, values)
    allow(registry).to receive(:each) do |&block|
      values.each { |value| block.call(value.respond_to?(:objid) ? value.objid : value) }
    end
  end

  def stub_membership_scan(*memberships)
    stub_instance_scan(membership_instances, memberships)
    memberships.each do |record|
      allow(Onetime::OrganizationMembership).to receive(:load).with(record.objid).and_return(record)
    end
  end

  def stub_organization_scan(*organizations)
    stub_instance_scan(instances, organizations)
    organizations.each do |org|
      allow(Onetime::Organization).to receive(:load).with(org.objid).and_return(org)
    end
  end

  def stub_domain_scan(*domains)
    stub_instance_scan(domain_instances, domains)
    domains.each do |domain|
      allow(Onetime::CustomDomain).to receive(:load).with(domain.objid).and_return(domain)
    end
  end

  def stub_membership_lookup(org, records)
    records.each do |customer_objid, record|
      allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
        .with(org.objid, customer_objid).and_return(record)
    end
  end

  # A RegistrySweep as a capture over these doubles would have produced it:
  # every organization listed and referenced, membership rows grouped by their
  # organization with the target's rows named, domains grouped by org_id. The
  # preflight re-loads each through the stubbed loaders.
  def registry_sweep(organizations: [], memberships: [], domains: [], failures: {})
    Auth::Operations::Customers::RegistrySweep.new(
      customer_objid: customer.objid,
      organization_ids: organizations.map(&:objid),
      referenced_org_ids: organizations.map(&:objid),
      membership_objids_by_org: memberships.group_by(&:organization_objid).transform_values { |rows| rows.map(&:objid) },
      target_membership_objids: memberships.select { |row| row.customer_objid == customer.objid }.map(&:objid),
      domain_objids_by_org: domains.group_by(&:org_id).transform_values { |rows| rows.map(&:objid) },
      failures: failures,
    )
  end

  describe 'already-deleted organization participation' do
    let(:reference) { 'organization:org-gone:members' }
    let(:redis) { double('read-only Redis') }
    let(:owners) { double('domain owners', hgetall: {}) }
    let(:orphan_indexes) { {} }
    let(:keys) { [] }

    before do
      allow(customer).to receive(:participations).and_return(collection([reference]))
      allow(instances).to receive(:member?).and_return(false)
      [Onetime::Organization, Onetime::OrganizationMembership, Onetime::CustomDomain].each do |model|
        allow(model).to receive(:dbclient).and_return(redis)
      end
      allow(redis).to receive(:scan_each) do |match:|
        keys.select { |key| File.fnmatch(match, key) }.each
      end
      [:contact_email_index, :extid_lookup, :stripe_customer_id_index, :stripe_subscription_id_index].each do |index|
        orphan_indexes[index] = double(index.to_s, hgetall: {})
        allow(Onetime::Organization).to receive(index).and_return(orphan_indexes[index])
      end
      allow(Onetime::CustomDomain).to receive(:owners).and_return(owners)
      allow(Onetime::CustomDomain).to receive(:load).and_return(nil)
    end

    def orphan_plan
      described_class.new(customer: customer).call
    end

    def expect_orphan_blocked
      plan = orphan_plan
      expect(plan).not_to be_executable
      expect(plan.actions).to be_empty
      expect(plan.blockers).to include(code: :dangling_customer_participation, reference: reference)
    end

    it 'plans an exact reference removal without saving or deleting anything' do
      expect(Onetime::Organization).not_to receive(:create!)
      expect_any_instance_of(Onetime::Organization).not_to receive(:save)
      expect_any_instance_of(Onetime::Organization).not_to receive(:destroy!)
      expect(customer).not_to receive(:untrack_participation)
      # Redis is a strict double: only the read operation above is accepted.
      plan = orphan_plan
      expect(plan).to be_executable
      action = plan.actions.fetch(0)
      expect(action.type).to eq(:remove_stale_participation)
      expect(action.reference).to eq(reference)
      expect(action.organization).to be_a(Onetime::Organization)
      expect(action.organization.objid).to eq('org-gone')
      expect(action.org_id).to eq('org-gone')
      expect(action.role).to eq('')
      expect(action.account_purge_context).to be_nil
      expect(plan.signature.first).to eq([[:remove_stale_participation, 'org-gone', '', reference]])
    end

    %w[organization org].each do |prefix|
      ['org.gone', 'org gone', '*', 'org/gone'].each do |objid|
        it "refuses malformed stale identifier #{objid.inspect} under #{prefix} without planning cleanup" do
          invalid = "#{prefix}:#{objid}:members"
          allow(customer).to receive(:participations).and_return(collection([invalid]))
          expect(customer).not_to receive(:untrack_participation_in)
          expect(customer.purge_pending_organization_checks).not_to receive(:add)
          expect(redis).not_to receive(:scan_each)

          plan = orphan_plan

          expect(plan).not_to be_executable
          expect(plan.actions).to be_empty
          expect(plan.blockers).to include(code: :dangling_customer_participation, reference: invalid)
          expect(customer.participations.to_a).to eq([invalid])
          expect(customer.purge_pending_organization_checks.to_a).to be_empty
        end
      end
    end

    describe 'durable pending organization checks' do
      let(:markers) { collection([reference]) }

      before do
        allow(customer).to receive(:participations).and_return(collection([]))
        allow(customer).to receive(:purge_pending_organization_checks).and_return(markers)
      end

      it 'blocks a fresh purge when receipts appeared after participation removal' do
        expect(orphan_plan).to be_executable
        keys << 'organization:org-gone:receipts'
        plan = orphan_plan
        expect(plan).not_to be_executable
        expect(plan.actions).to be_empty
        expect(plan.blockers).to include(
          { code: :dangling_customer_participation, reference: reference },
          { code: :orphan_organization_dependencies_remain, org_id: 'org-gone' },
        )
      end

      it 'allows absent dependencies without planning removal or clearing the marker' do
        expect(markers).not_to receive(:remove)
        expect(markers).not_to receive(:clear)
        plan = orphan_plan
        expect(plan).to be_executable
        expect(plan.actions).to be_empty
        expect(customer.purge_pending_organization_checks.to_a).to eq([reference])
      end

      it 'exposes marker-only checks for revalidation after persisted markers are destroyed' do
        checker = described_class.new(customer: customer)
        expect(checker.pending_organization_checks).to eq([])
        plan = checker.call
        expect(plan).to be_executable
        expect(plan.actions).to be_empty
        action = checker.pending_organization_checks.fetch(0)
        expect(action.type).to eq(:remove_stale_participation)
        expect(action.reference).to eq(reference)
        expect(action.organization.objid).to eq('org-gone')
        expect(action.org_id).to eq('org-gone')
        expect(action.role).to eq('')

        allow(markers).to receive(:to_a).and_return([])
        keys << 'organization:org-gone:receipts'
        expect(described_class.new(customer: nil).stale_participation_blockers(action))
          .to include(code: :orphan_organization_dependencies_remain, org_id: 'org-gone')
      end

      it 'exposes every valid marker even when dependency checks block the plan' do
        aliases = [reference, 'org:org-gone:members']
        allow(markers).to receive(:to_a).and_return(aliases + ['invalid'])
        keys << 'organization:org-gone:receipts'
        checker = described_class.new(customer: customer)
        plan = checker.call
        expect(plan).not_to be_executable
        expect(plan.actions).to be_empty
        expect(checker.pending_organization_checks.map(&:reference)).to eq(aliases.sort)
      end

      it 'checks legacy aliases without needing a participation' do
        allow(markers).to receive(:to_a).and_return(['org:org-gone:members'])
        keys << 'organization:org-gone:receipts'
        expect(orphan_plan.blockers).to include(
          code: :dangling_customer_participation, reference: 'org:org-gone:members',
        )
      end

      it 'does not duplicate a removal action when its marker also exists' do
        allow(customer).to receive(:participations).and_return(collection([reference]))
        expect(orphan_plan.actions.map(&:reference)).to eq([reference])
      end

      it 'fails closed when the marker set is unreadable' do
        allow(markers).to receive(:to_a).and_raise(IOError)
        plan = orphan_plan
        expect(plan).not_to be_executable
        expect(plan.blockers).to include(code: :purge_pending_organization_checks_lookup_failed, message: 'IOError')
      end

      it 'fails closed when dependency evidence for a marker is unreadable' do
        allow(owners).to receive(:hgetall).and_raise(IOError)
        plan = orphan_plan
        expect(plan).not_to be_executable
        expect(plan.blockers).to include(code: :organization_evidence_incomplete, org_id: 'org-gone', message: 'IOError')
      end

      ['', 'organization::members', 'organization:org-gone:domains',
       'organization:org-gone:members:extra', "organization:org-gone:members\n",
       'organization:org.gone:members', 'org:org.gone:members',
       'organization:org gone:members', 'organization:*:members', 'unknown:org-gone:members', nil, 123].each do |invalid|
        it "fails closed for malformed marker #{invalid.inspect}" do
          allow(markers).to receive(:to_a).and_return([reference, invalid])
          plan = orphan_plan
          expect(plan).not_to be_executable
          expect(plan.actions).to be_empty
          expect(plan.blockers).to include(code: :invalid_purge_pending_organization_check, reference: invalid.to_s)
        end
      end
    end

    describe '#stale_participation_blockers' do
      let(:completed_action) { orphan_plan.actions.fetch(0) }

      before do
        completed_action
        allow(customer).to receive(:participations).and_return(collection([]))
      end

      it 'returns no blockers after cleanup without reading the deleted customer' do
        checker = described_class.new(customer: nil)
        expect(checker.stale_participation_blockers(completed_action)).to eq([])
      end

      it 'uses fresh evidence in subsequent checkers after the reverse index is gone' do
        checker = described_class.new(customer: customer)
        expect(checker.stale_participation_blockers(completed_action)).to eq([])
        keys << 'organization:org-gone:receipts'
        subsequent = described_class.new(customer: customer)
        expect(subsequent.call.actions).to be_empty
        expect(subsequent.stale_participation_blockers(completed_action)).to contain_exactly(
          { code: :dangling_customer_participation, reference: reference },
          { code: :orphan_organization_dependencies_remain, org_id: 'org-gone' },
        )
        keys.clear
        final = described_class.new(customer: nil)
        expect(final.stale_participation_blockers(completed_action)).to eq([])
      end

      it 'detects a recreated organization after customer teardown' do
        allow(Onetime::Organization).to receive(:load).with('org-gone')
          .and_return(organization(objid: 'org-gone'))
        expect(described_class.new(customer: nil).stale_participation_blockers(completed_action))
          .to include(code: :orphan_organization_dependencies_remain, org_id: 'org-gone')
      end

      it 'detects a new domain reference after customer teardown' do
        allow(owners).to receive(:hgetall).and_return('late-domain' => 'org-gone')
        expect(described_class.new(customer: nil).stale_participation_blockers(completed_action))
          .to include(code: :orphan_organization_dependencies_remain, org_id: 'org-gone')
      end

      it 'fails closed on a subsequent read failure without changing discovery state' do
        checker = described_class.new(customer: customer)
        allow(redis).to receive(:scan_each).with(match: 'organization:*').and_raise(IOError)
        expect(checker.stale_participation_blockers(completed_action)).to contain_exactly(
          { code: :dangling_customer_participation, reference: reference },
          { code: :organization_evidence_incomplete, org_id: 'org-gone', message: 'IOError' },
        )
        expect(checker.call.blockers).to be_empty
      end

      it 'uses the same blocker taxonomy during discovery' do
        keys << 'organization:org-gone:members'
        checker = described_class.new(customer: customer)
        expected = checker.stale_participation_blockers(completed_action)
        allow(customer).to receive(:participations).and_return(collection([reference]))
        expect(orphan_plan.blockers).to match_array(expected)
      end
    end

    it 'preserves each alias and sorts deterministically regardless of set order' do
      aliases = [reference, 'org:org-gone:members']
      allow(customer).to receive(:participations).and_return(collection(aliases))
      first = orphan_plan
      allow(customer).to receive(:participations).and_return(collection(aliases.reverse))
      second = orphan_plan
      expect(first.actions.map(&:reference)).to eq(aliases.sort)
      expect(second.signature).to eq(first.signature)
      allow(customer).to receive(:participations).and_return(collection([aliases.last]))
      expect(orphan_plan.signature).not_to eq(first.signature)
    end

    describe 'checker-local dependency evidence' do
      let(:aliases) { [reference, 'org:org-gone:members'] }

      before do
        allow(customer).to receive(:participations).and_return(collection(aliases))
        allow(customer).to receive(:purge_pending_organization_checks).and_return(collection(aliases))
      end

      it 'scans once for discovery, markers and retained checks of either alias' do
        %w[organization:* org:* org_membership:* custom_domain:*:object].each do |pattern|
          expect(redis).to receive(:scan_each).with(match: pattern).once.and_return([].each)
        end
        checker = described_class.new(customer: customer)
        plan = checker.call

        expect(plan).to be_executable
        expect(plan.actions.map(&:reference)).to eq(aliases.sort)
        expect(checker.pending_organization_checks.map(&:reference)).to eq(aliases.sort)
        (plan.actions + checker.pending_organization_checks).each do |action|
          expect(checker.stale_participation_blockers(action)).to eq([])
        end
      end

      it 'keeps blockers specific to each reference when dependency evidence is shared' do
        keys << 'organization:org-gone:receipts'
        checker = described_class.new(customer: customer)
        expect(checker).to receive(:orphan_dependencies?).once.and_call_original
        plan = checker.call

        expect(plan).not_to be_executable
        expect(plan.actions).to be_empty
        expect(plan.blockers).to contain_exactly(
          *aliases.map { |alias_reference| { code: :dangling_customer_participation, reference: alias_reference } },
          { code: :orphan_organization_dependencies_remain, org_id: 'org-gone' },
        )
        checker.pending_organization_checks.each do |action|
          expect(checker.stale_participation_blockers(action)).to contain_exactly(
            { code: :dangling_customer_participation, reference: action.reference },
            { code: :orphan_organization_dependencies_remain, org_id: 'org-gone' },
          )
        end
      end

      it 'shares read failures without losing either reference or retrying within the checker' do
        allow(owners).to receive(:hgetall).and_raise(IOError)
        checker = described_class.new(customer: customer)
        expect(checker).to receive(:orphan_dependencies?).once.and_call_original
        plan = checker.call

        expect(plan).not_to be_executable
        expect(plan.actions).to be_empty
        expect(plan.blockers).to contain_exactly(
          *aliases.map { |alias_reference| { code: :dangling_customer_participation, reference: alias_reference } },
          { code: :organization_evidence_incomplete, org_id: 'org-gone', message: 'IOError' },
        )
        checker.pending_organization_checks.each do |action|
          expect(checker.stale_participation_blockers(action)).to contain_exactly(
            { code: :dangling_customer_participation, reference: action.reference },
            { code: :organization_evidence_incomplete, org_id: 'org-gone', message: 'IOError' },
          )
        end

        allow(owners).to receive(:hgetall).and_return({})
        expect(orphan_plan).to be_executable
      end

      it 'does not reuse an absent dependency result for another organization' do
        other_reference = 'organization:org-other:members'
        allow(customer).to receive(:purge_pending_organization_checks).and_return(collection([other_reference]))
        keys << 'organization:org-other:receipts'
        plan = orphan_plan

        expect(plan).not_to be_executable
        expect(plan.actions.map(&:reference)).to eq(aliases.sort)
        expect(plan.blockers).to contain_exactly(
          { code: :dangling_customer_participation, reference: other_reference },
          { code: :orphan_organization_dependencies_remain, org_id: 'org-other' },
        )
      end
    end

    it 'preserves the original three-element signature for existing actions' do
      actions = [:delete_organization, :remove_membership].map do |type|
        described_class::Action.new(
          type: type, organization: organization, org_id: 'on_personal', role: 'owner', reference: 'ignored',
        )
      end
      plan = described_class::Plan.new(actions: actions, blockers: [])
      expect(plan.signature.first).to eq([
        [:delete_organization, 'org-personal', 'owner'],
        [:remove_membership, 'org-personal', 'owner'],
      ])
    end

    it 'checks the physical through-model layout, not only its logical composite objid' do
      id = Onetime::OrganizationMembership.composite_objid('org-gone', customer.objid)
      record = Onetime::OrganizationMembership.new(objid: id)
      expect(record.dbkey).to eq('org_membership:organization:org-gone:customer:cust-target:org_membership:object')
      keys << record.dbkey
      expect_orphan_blocked
    end

    [
      'organization:org-gone:object',
      'organization:org-gone:members',
      'organization:org-gone:pending_invitations',
      'organization:org-gone:domains',
      'organization:org-gone:receipts',
      'organization:org-gone:urls',
      'org:org-gone:members',
      'org_membership:organization:org-gone:customer:other:org_membership:materialized_entitlements',
      'org_membership:org:org-gone:customer:other:org_membership:object',
    ].each do |key|
      it "blocks residual key #{key}" do
        keys << key
        expect_orphan_blocked
      end
    end

    it 'blocks a residual organization registry entry' do
      allow(instances).to receive(:member?).and_return(true)
      expect_orphan_blocked
    end

    [:contact_email_index, :extid_lookup, :stripe_customer_id_index, :stripe_subscription_id_index].each do |index|
      it "blocks residual #{index} claims" do
        allow(orphan_indexes.fetch(index)).to receive(:hgetall).and_return('claim' => 'org-gone')
        expect_orphan_blocked
      end
    end

    it 'blocks a membership found only through the registry' do
      stub_membership_scan(membership(org_objid: 'org-gone', customer_objid: 'other', role: 'member', objid: 'invite'))
      expect_orphan_blocked
    end

    it 'blocks an unregistered invitation record' do
      keys << 'org_membership:invite:object'
      allow(Onetime::OrganizationMembership).to receive(:load).with('invite')
        .and_return(membership(org_objid: 'org-gone', customer_objid: nil, role: 'member', status: 'pending', objid: 'invite'))
      expect_orphan_blocked
    end

    it 'blocks an owner index entry even if its domain record is gone' do
      allow(owners).to receive(:hgetall).and_return('gone-domain' => 'org-gone')
      expect_orphan_blocked
    end

    it 'blocks a domain found only through the registry' do
      stub_domain_scan(double('Domain', objid: 'domain', org_id: 'org-gone'))
      expect_orphan_blocked
    end

    it 'blocks an unregistered domain record' do
      keys << 'custom_domain:domain:object'
      allow(Onetime::CustomDomain).to receive(:load).with('domain')
        .and_return(double('Domain', org_id: 'org-gone'))
      expect_orphan_blocked
    end

    it 'does not confuse another organization with an identifier prefix match' do
      keys.concat(['organization:org-gone-other:members',
                   'org_membership:organization:org-gone-other:customer:other:org_membership:object'])
      expect(orphan_plan).to be_executable
    end

    %w[organization:* org:* org_membership:* custom_domain:*:object].each do |pattern|
      it "fails closed when scanning #{pattern} fails" do
        allow(redis).to receive(:scan_each).with(match: pattern).and_raise(IOError)
        expect_orphan_blocked
        expect(orphan_plan.blockers).to include(code: :organization_evidence_incomplete, org_id: 'org-gone', message: 'IOError')
      end
    end

    it 'also supports deep discovery without changing the cleanup interface' do
      plan = described_class.new(customer: customer, deep: true).call
      expect(plan).to be_executable
      expect(plan.signature).to eq(orphan_plan.signature)
    end

    it 'rechecks absence before permitting cleanup' do
      allow(Onetime::Organization).to receive(:load).with('org-gone')
        .and_return(nil, organization(objid: 'org-gone'))
      expect_orphan_blocked
    end

    it 'fails closed when the organization registry is unreadable' do
      allow(instances).to receive(:member?).and_raise(IOError)
      expect_orphan_blocked
    end

    it 'fails closed when an organization index is unreadable' do
      allow(orphan_indexes.fetch(:extid_lookup)).to receive(:hgetall).and_raise(IOError)
      expect_orphan_blocked
    end

    it 'fails closed when the membership registry is unreadable' do
      allow(membership_instances).to receive(:each).and_raise(IOError)
      expect_orphan_blocked
    end

    it 'fails closed when a membership record is unreadable' do
      stub_instance_scan(membership_instances, ['invite'])
      allow(Onetime::OrganizationMembership).to receive(:load).with('invite').and_raise(IOError)
      expect_orphan_blocked
    end

    it 'fails closed when the domain registry is unreadable' do
      allow(domain_instances).to receive(:each).and_raise(IOError)
      expect_orphan_blocked
    end

    it 'fails closed when a domain record cannot be read' do
      stub_instance_scan(domain_instances, ['domain'])
      allow(Onetime::CustomDomain).to receive(:load).with('domain').and_raise(IOError)
      expect_orphan_blocked
    end

    it 'fails closed when the owner index cannot be read' do
      allow(owners).to receive(:hgetall).and_raise(IOError)
      expect_orphan_blocked
    end
  end

  it 'does not sweep orphan keyspaces or registries for healthy shallow discovery' do
    expect(Onetime::Organization).not_to receive(:dbclient)
    expect(Onetime::OrganizationMembership).not_to receive(:dbclient)
    expect(Onetime::CustomDomain).not_to receive(:dbclient)
    expect(membership_instances).not_to receive(:each)
    expect(domain_instances).not_to receive(:each)
    expect(described_class.new(customer: customer).call).to be_executable
  end

  it 'discovers and plans a strict empty personal workspace from all agreeing indexes' do
    expect(Onetime::Organization).not_to receive(:dbclient)
    expect(Onetime::OrganizationMembership).not_to receive(:dbclient)
    expect(Onetime::CustomDomain).not_to receive(:dbclient)
    expect(membership_instances).not_to receive(:each)
    expect(domain_instances).not_to receive(:each)
    org = organization
    owner_membership = membership(
      org_objid: org.objid,
      customer_objid: customer.objid,
      role: 'owner',
    )
    allow(customer).to receive(:participations)
      .and_return(collection(["organization:#{org.objid}:members"]))
    allow(customer).to receive(:organization_instances).and_return(collection([org]))
    stub_organization_scan(org)
    stub_membership_scan(owner_membership)
    stub_membership_lookup(org, customer.objid => owner_membership)
    allow(Onetime::Customer).to receive(:load).with(customer.objid).and_return(customer)
    allow(contact_index).to receive(:get).with('target@example.com').and_return(org.objid)

    plan = described_class.new(customer: customer).call

    expect(plan).to be_executable
    expect(plan.blockers).to be_empty
    expect(plan.actions.map(&:type)).to eq([:delete_organization])
    expect(plan.actions.first.org_id).to eq('on_personal')
    expect(plan.actions.first.account_purge_context)
      .to be_a(described_class::AccountPurgeContext)
  end

  it 'plans a consistent ordinary non-owner membership for semantic removal' do
    owner = double('Owner', objid: 'cust-owner')
    org = organization(
      objid: 'org-shared',
      extid: 'on_shared',
      owner_id: owner.objid,
      created_by: owner.objid,
      contact_email: 'owner@example.com',
      is_default: 'false',
      members: collection([customer.objid, owner.objid]),
    )
    target_membership = membership(
      org_objid: org.objid,
      customer_objid: customer.objid,
      role: 'member',
    )
    owner_membership = membership(
      org_objid: org.objid,
      customer_objid: owner.objid,
      role: 'owner',
    )

    allow(customer).to receive(:participations)
      .and_return(collection(["organization:#{org.objid}:members"]))
    allow(customer).to receive(:organization_instances).and_return(collection([org]))
    stub_organization_scan(org)
    stub_membership_scan(target_membership, owner_membership)
    stub_membership_lookup(
      org,
      customer.objid => target_membership,
      owner.objid => owner_membership,
    )
    allow(Onetime::Customer).to receive(:load).with(customer.objid).and_return(customer)
    allow(Onetime::Customer).to receive(:load).with(owner.objid).and_return(owner)
    allow(contact_index).to receive(:get).with('owner@example.com').and_return(org.objid)

    plan = described_class.new(customer: customer).call

    expect(plan).to be_executable
    expect(plan.actions.map(&:type)).to eq([:remove_membership])
    expect(plan.actions.first.role).to eq('member')
  end

  it 'plans membership removal from a workspace that carries no contact email' do
    # Workspaces created through the product UI have no contact email: the
    # modal submits display_name and description only, so nothing was ever
    # reserved in the index and an absent address is not drift.
    owner = double('Owner', objid: 'cust-owner')
    org = organization(
      objid: 'org-ui-created',
      extid: 'on_ui_created',
      owner_id: owner.objid,
      created_by: owner.objid,
      contact_email: nil,
      is_default: 'false',
      members: collection([customer.objid, owner.objid]),
    )
    target_membership = membership(
      org_objid: org.objid,
      customer_objid: customer.objid,
      role: 'member',
    )
    owner_membership = membership(
      org_objid: org.objid,
      customer_objid: owner.objid,
      role: 'owner',
    )

    allow(customer).to receive(:participations)
      .and_return(collection(["organization:#{org.objid}:members"]))
    allow(customer).to receive(:organization_instances).and_return(collection([org]))
    stub_organization_scan(org)
    stub_membership_scan(target_membership, owner_membership)
    stub_membership_lookup(
      org,
      customer.objid => target_membership,
      owner.objid => owner_membership,
    )
    allow(Onetime::Customer).to receive(:load).with(customer.objid).and_return(customer)
    allow(Onetime::Customer).to receive(:load).with(owner.objid).and_return(owner)

    plan = described_class.new(customer: customer).call

    expect(plan).to be_executable
    expect(plan.blockers).to be_empty
    expect(plan.actions.map(&:type)).to eq([:remove_membership])
  end

  it 'discovers an active target membership even when both relationship indexes omit it' do
    owner = double('Owner', objid: 'cust-owner')
    org = organization(
      objid: 'org-drifted',
      extid: 'on_drifted',
      owner_id: owner.objid,
      created_by: owner.objid,
      contact_email: 'owner@example.com',
      is_default: 'false',
      members: collection([owner.objid]),
    )
    target_membership = membership(
      org_objid: org.objid,
      customer_objid: customer.objid,
      role: 'member',
    )
    owner_membership = membership(
      org_objid: org.objid,
      customer_objid: owner.objid,
      role: 'owner',
    )

    stub_organization_scan(org)
    stub_membership_scan(target_membership, owner_membership)
    stub_membership_lookup(
      org,
      customer.objid => target_membership,
      owner.objid => owner_membership,
    )
    allow(Onetime::Customer).to receive(:load).with(customer.objid).and_return(customer)
    allow(Onetime::Customer).to receive(:load).with(owner.objid).and_return(owner)
    allow(contact_index).to receive(:get).with('owner@example.com').and_return(org.objid)

    # Reachable only through the global registry sweep: the customer's own
    # reverse indexes do not name this organization.
    sweep = registry_sweep(organizations: [org], memberships: [target_membership, owner_membership])
    plan  = described_class.new(customer: customer, deep: true, registry_sweep: sweep).call

    expect(plan).not_to be_executable
    expect(plan.blockers.map { |blocker| blocker[:code] })
      .to include(:membership_index_drift, :target_membership_drift)
    expect(plan.actions).to be_empty
  end

  it 'captures the registry sweep once and exposes it for reuse' do
    sweep = registry_sweep
    allow(Auth::Operations::Customers::RegistrySweep).to receive(:capture)
      .with(customer_objid: customer.objid).and_return(sweep)

    checker = described_class.new(customer: customer, deep: true)
    checker.call

    expect(checker.registry_sweep).to be(sweep)
    expect(Auth::Operations::Customers::RegistrySweep).to have_received(:capture).once

    reused = described_class.new(customer: customer, deep: true, registry_sweep: sweep)
    reused.call
    expect(reused.registry_sweep).to be(sweep)
    expect(Auth::Operations::Customers::RegistrySweep).to have_received(:capture).once
  end

  it 'hands the sweep to the deletion capability so the recheck does not rescan' do
    org              = organization
    owner_membership = membership(org_objid: org.objid, customer_objid: customer.objid, role: 'owner')
    allow(customer).to receive(:participations)
      .and_return(collection(["organization:#{org.objid}:members"]))
    allow(customer).to receive(:organization_instances).and_return(collection([org]))
    stub_organization_scan(org)
    stub_membership_scan(owner_membership)
    stub_membership_lookup(org, customer.objid => owner_membership)
    allow(Onetime::Customer).to receive(:load).with(customer.objid).and_return(customer)
    allow(contact_index).to receive(:get).with('target@example.com').and_return(org.objid)
    allow(Auth::Operations::Customers::RegistrySweep).to receive(:capture)

    sweep = registry_sweep(organizations: [org], memberships: [owner_membership])
    plan  = described_class.new(customer: customer, deep: true, registry_sweep: sweep).call

    expect(plan.actions.map(&:type)).to eq([:delete_organization])
    context = plan.actions.first.account_purge_context
    expect(context.authorized_for?(org)).to be(true)
    expect(Auth::Operations::Customers::RegistrySweep).not_to have_received(:capture)
  end

  it 'ignores a registry sweep on a shallow preflight' do
    org              = organization
    owner_membership = membership(org_objid: org.objid, customer_objid: customer.objid, role: 'owner')
    allow(customer).to receive(:participations)
      .and_return(collection(["organization:#{org.objid}:members"]))
    allow(customer).to receive(:organization_instances).and_return(collection([org]))
    stub_organization_scan(org)
    stub_membership_scan(owner_membership)
    stub_membership_lookup(org, customer.objid => owner_membership)
    allow(Onetime::Customer).to receive(:load).with(customer.objid).and_return(customer)
    allow(contact_index).to receive(:get).with('target@example.com').and_return(org.objid)
    allow(Auth::Operations::Customers::RegistrySweep).to receive(:capture)

    sweep   = registry_sweep(organizations: [org], memberships: [owner_membership])
    checker = described_class.new(customer: customer, registry_sweep: sweep)
    plan    = checker.call

    # Shallow discovery reaches the workspace through the customer's own
    # indexes, exactly as without the sweep: the sweep adds no evidence.
    expect(plan.actions.map(&:type)).to eq([:delete_organization])
    expect(checker.registry_sweep).to be_nil
    expect(Auth::Operations::Customers::RegistrySweep).not_to have_received(:capture)
  end

  it 'drops a swept organization that no longer references the customer' do
    owner = double('Owner', objid: 'cust-owner')
    org   = organization(
      objid: 'org-left',
      extid: 'on_left',
      owner_id: owner.objid,
      created_by: owner.objid,
      contact_email: 'owner@example.com',
      is_default: 'false',
      members: collection([owner.objid]),
    )
    owner_membership = membership(org_objid: org.objid, customer_objid: owner.objid, role: 'owner')
    # Named by the sweep (the row existed at capture) but removed since, as
    # the purge's own remove_membership action does.
    removed_row = Onetime::OrganizationMembership.composite_objid(org.objid, customer.objid)
    stub_organization_scan(org)
    stub_membership_scan(owner_membership)
    stub_membership_lookup(org, owner.objid => owner_membership)
    allow(Onetime::Customer).to receive(:load).with(owner.objid).and_return(owner)

    sweep = Auth::Operations::Customers::RegistrySweep.new(
      customer_objid: customer.objid,
      organization_ids: [org.objid],
      referenced_org_ids: [org.objid],
      membership_objids_by_org: { org.objid => [owner_membership.objid, removed_row] },
      target_membership_objids: [removed_row],
    )
    plan = described_class.new(customer: customer, deep: true, registry_sweep: sweep).call

    expect(plan).to be_executable
    expect(plan.actions).to be_empty
    expect(plan.blockers).to be_empty
    expect(Onetime::Organization).to have_received(:load).with(org.objid)
    expect(Onetime::OrganizationMembership).to have_received(:load).with(removed_row)
  end

  it 'reports an orphan membership row that still names the customer' do
    row = membership(org_objid: 'org-vanished', customer_objid: customer.objid, role: 'member')
    stub_membership_scan(row)

    sweep = registry_sweep(memberships: [row])
    plan  = described_class.new(customer: customer, deep: true, registry_sweep: sweep).call

    expect(plan).not_to be_executable
    expect(plan.blockers).to include(code: :orphan_customer_membership, membership_id: row.objid)
  end

  it 'turns a sweep that could not list a registry into the matching blockers' do
    sweep = registry_sweep(
      failures: { organizations: 'IOError', memberships: 'Familia::Problem', domains: 'IOError' },
    )
    plan = described_class.new(customer: customer, deep: true, registry_sweep: sweep).call

    expect(plan).not_to be_executable
    expect(plan.blockers).to include(
      { code: :organization_scan_failed, message: 'IOError' },
      { code: :membership_scan_failed, message: 'Familia::Problem' },
      { code: :domain_scan_failed, message: 'IOError' },
    )
  end

  it 'fails closed on drift and billing state, not on the account own workspace content' do
    org = organization(
      members: collection([customer.objid, 'cust-stale']),
      domain_count: 1,
      pending_invitation_count: 1,
      pending_invitations: collection(['pending-1']),
      receipt_count: 2,
      stripe_customer_id: 'cus_retained',
      billing_live?: true,
      description: 'retained description',
    )
    owner_membership = membership(
      org_objid: org.objid,
      customer_objid: customer.objid,
      role: 'owner',
    )

    allow(customer).to receive(:participations)
      .and_return(collection(["organization:#{org.objid}:members"]))
    allow(customer).to receive(:organization_instances).and_return(collection([org]))
    stub_organization_scan(org)
    stub_membership_scan(owner_membership)
    stub_membership_lookup(org, customer.objid => owner_membership, 'cust-stale' => nil)
    allow(Onetime::Customer).to receive(:load).with(customer.objid).and_return(customer)
    allow(Onetime::Customer).to receive(:load).with('cust-stale').and_return(nil)
    allow(contact_index).to receive(:get).with('target@example.com').and_return(org.objid)

    plan = described_class.new(customer: customer).call
    codes = plan.blockers.map { |blocker| blocker[:code] }

    expect(plan).not_to be_executable
    expect(codes).to include(
      :stale_members,
      :membership_record_missing,
      :membership_index_drift,
      :other_members,
      :has_domains,
      :pending_invitation_drift,
      :billing_state,
    )
    # Receipts, outstanding invitations and the workspace description are
    # deleted WITH the organization, so they are not reasons to refuse.
    expect(codes).not_to include(:has_receipts, :pending_invitations, :retained_organization_data)
    expect(plan.actions).to be_empty
  end

  it 'reports deletable workspace content as action evidence rather than a blocker' do
    org = organization(
      receipt_count: 3,
      pending_invitation_count: 0,
      contact_email: 'Billing.Sync@Example.com',
      description: 'retained description',
    )
    owner_membership = membership(
      org_objid: org.objid,
      customer_objid: customer.objid,
      role: 'owner',
    )
    allow(customer).to receive(:participations)
      .and_return(collection(["organization:#{org.objid}:members"]))
    allow(customer).to receive(:organization_instances).and_return(collection([org]))
    stub_membership_lookup(org, customer.objid => owner_membership)
    allow(Onetime::Organization).to receive(:load).with(org.objid).and_return(org)
    allow(Onetime::Customer).to receive(:load).with(customer.objid).and_return(customer)
    allow(contact_index).to receive(:get).with(org.contact_email).and_return(org.objid)

    plan = described_class.new(customer: customer).call

    expect(plan).to be_executable
    expect(plan.actions.map(&:type)).to eq([:delete_organization])
    expect(plan.actions.first.notes)
      .to include(:has_receipts, :contact_email_mismatch, :retained_description)
  end

  it 'blocks a half-finished migration, which owns rows outside this workspace' do
    org = organization(migration_status: 'in_progress')
    owner_membership = membership(
      org_objid: org.objid,
      customer_objid: customer.objid,
      role: 'owner',
    )
    allow(customer).to receive(:participations)
      .and_return(collection(["organization:#{org.objid}:members"]))
    allow(customer).to receive(:organization_instances).and_return(collection([org]))
    stub_membership_lookup(org, customer.objid => owner_membership)
    allow(Onetime::Organization).to receive(:load).with(org.objid).and_return(org)
    allow(Onetime::Customer).to receive(:load).with(customer.objid).and_return(customer)
    allow(contact_index).to receive(:get).with('target@example.com').and_return(org.objid)

    plan = described_class.new(customer: customer).call

    expect(plan).not_to be_executable
    expect(plan.blockers).to include(hash_including(code: :migration_in_flight))
  end

  it 'accepts a legacy owner_id/created_by that still carries the custid' do
    org = organization(owner_id: 'target@example.com', created_by: 'target@example.com')
    owner_membership = membership(
      org_objid: org.objid,
      customer_objid: customer.objid,
      role: 'owner',
    )
    allow(customer).to receive(:participations)
      .and_return(collection(["organization:#{org.objid}:members"]))
    allow(customer).to receive(:organization_instances).and_return(collection([org]))
    stub_membership_lookup(org, customer.objid => owner_membership)
    allow(Onetime::Organization).to receive(:load).with(org.objid).and_return(org)
    allow(Onetime::Customer).to receive(:load).with(customer.objid).and_return(customer)
    allow(contact_index).to receive(:get).with('target@example.com').and_return(org.objid)

    plan = described_class.new(customer: customer).call
    codes = plan.blockers.map { |blocker| blocker[:code] }

    expect(codes).not_to include(:owner_id_mismatch, :creator_mismatch)
    expect(plan.actions.map(&:type)).to eq([:delete_organization])
  end

  describe 'historical data on an otherwise eligible personal workspace' do
    let(:org) { organization }
    let(:owner_membership) do
      membership(org_objid: org.objid, customer_objid: customer.objid, role: 'owner')
    end

    before do
      allow(customer).to receive(:custid).and_return(customer.objid)
      allow(customer).to receive(:participations)
        .and_return(collection(["organization:#{org.objid}:members"]))
      allow(customer).to receive(:organization_instances).and_return(collection([org]))
      stub_organization_scan(org)
      stub_membership_scan(owner_membership)
      stub_membership_lookup(org, customer.objid => owner_membership)
      allow(Onetime::Customer).to receive(:load).with(customer.objid).and_return(customer)
      allow(contact_index).to receive(:get).with(customer.email).and_return(org.objid)
    end

    def plan
      described_class.new(customer: customer).call
    end

    it 'accepts completed migration provenance without changing the source fields' do
      allow(org).to receive_messages(
        migration_status: 'completed', migrated_at: '1700000000',
        v1_identifier: customer.dbkey, v1_source_custid: customer.email,
        migration_comment: 'created_synthesized',
      )
      expect(org).not_to receive(:save)
      expect(customer).not_to receive(:save)

      expect(plan).to be_executable
    end

    it 'accepts provenance-only organizations created by create_from_v1_customer!' do
      allow(org).to receive(:v1_source_custid).and_return(customer.email)

      expect(plan).to be_executable
    end

    %w[pending migrating in_progress failed skipped unknown].each do |status|
      it "refuses explicit organization migration status #{status}" do
        allow(org).to receive(:migration_status).and_return(status)

        expect(plan.blockers).to include(hash_including(code: :migration_in_flight, org_id: org.extid))
        expect(plan.actions).to be_empty
      end

      it "refuses customer migration status #{status} even when the organization is completed" do
        allow(customer).to receive(:migration_status).and_return(status)
        allow(org).to receive(:migration_status).and_return('completed')

        expect(plan).not_to be_executable
        expect(plan.blockers).to include(hash_including(code: :migration_in_flight))
      end
    end

    it 'accepts a creator matching the preserved v1 identity after the customer changes email' do
      allow(customer).to receive(:v1_custid).and_return('old@example.com')
      allow(org).to receive(:created_by).and_return('old@example.com')

      expect(plan).to be_executable
    end

    it 'does not accept a creator solely because it matches the current email' do
      allow(org).to receive(:created_by).and_return(customer.email)

      expect(plan.blockers).to include(hash_including(code: :creator_mismatch))
    end

    it 'does not accept legacy creator evidence from the organization alone' do
      allow(org).to receive_messages(created_by: 'old@example.com', v1_source_custid: 'old@example.com')

      expect(plan.blockers).to include(hash_including(code: :creator_mismatch))
    end

    it 'does not broaden owner identity matching to historical email aliases' do
      allow(customer).to receive(:v1_custid).and_return('old@example.com')
      allow(org).to receive_messages(owner_id: 'old@example.com', created_by: 'old@example.com')

      expect(plan.blockers).to include(hash_including(code: :owner_id_mismatch))
    end

    context 'when the migration generator omitted created_by' do
      before do
        allow(customer).to receive(:v1_custid).and_return('old@example.com')
        allow(org).to receive_messages(
          created_by: nil, migration_status: 'completed',
          v1_identifier: customer.dbkey, v1_source_custid: 'old@example.com',
        )
      end

      it 'accepts completed provenance bound to the target customer key and legacy identity' do
        expect(plan).to be_executable
      end

      {
        v1_identifier: 'customer:another-customer:object',
        v1_source_custid: 'another@example.com',
        migration_status: nil,
        created_by: 'another-customer',
      }.each do |field, value|
        it "refuses contradictory or missing #{field}" do
          allow(org).to receive(field).and_return(value)

          expect(plan.blockers).to include(hash_including(code: :creator_mismatch))
          expect(plan.actions).to be_empty
        end
      end
    end

    {
      stripe_customer_id: 'cus_history',
      stripe_checkout_email: 'billing@example.com',
      billing_email: 'billing@example.com',
      email_hash: 'historical-hash',
      email_hash_synced_at: '2025-01-01@00:00Z',
      subscription_period_end: 1700000000,
      subscription_federated_at: 1700000000,
      federation_notification_dismissed_at: 1700000000,
      complimentary: 'true',
      planid: 'legacy_paid_plan',
    }.each do |field, value|
      it "does not refuse solely for historical #{field}" do
        allow(org).to receive(field).and_return(value)

        expect(plan).to be_executable
      end
    end

    %w[canceled incomplete incomplete_expired paused].each do |status|
      it "accepts non-live #{status} billing with retained Stripe identifiers" do
        allow(org).to receive_messages(
          subscription_status: status, stripe_customer_id: 'cus_history',
          stripe_subscription_id: 'sub_history',
        )

        expect(plan).to be_executable
      end
    end

    %w[active trialing past_due unpaid].each do |status|
      it "refuses #{status} billing even without local Stripe identifiers" do
        allow(org).to receive_messages(subscription_status: status, billing_live?: true)

        expect(plan.blockers).to include(hash_including(code: :billing_state))
        expect(plan.actions).to be_empty
      end
    end

    it 'refuses an unknown subscription status' do
      allow(org).to receive(:subscription_status).and_return('unknown')

      expect(plan.blockers).to include(hash_including(code: :billing_state))
    end

    it 'refuses a subscription identifier with no known status' do
      allow(org).to receive(:stripe_subscription_id).and_return('sub_unknown')

      expect(plan.blockers).to include(hash_including(code: :billing_state))
    end

    {
      pending_currency_migration: 'true',
      migration_target_price_id: 'price_next',
      migration_effective_after: 1700000000,
    }.each do |field, value|
      it "still refuses #{field} on a canceled subscription" do
        allow(org).to receive_messages(subscription_status: 'canceled', field => value)

        expect(plan.blockers).to include(hash_including(code: :billing_state))
        expect(plan.actions).to be_empty
      end
    end

    [false, 'false', nil, ''].each do |value|
      it "accepts an inactive currency migration flag #{value.inspect}" do
        allow(org).to receive(:pending_currency_migration).and_return(value)

        expect(plan).to be_executable
      end
    end

    it 'refuses when the billing read fails rather than treating it as historical' do
      allow(org).to receive(:billing_live?).and_raise(Familia::Problem, 'unavailable')

      expect(plan.blockers).to include(hash_including(code: :organization_evidence_incomplete))
      expect(plan.actions).to be_empty
    end

    it 'invalidates an issued deletion capability when canceled billing becomes live' do
      allow(org).to receive_messages(subscription_status: 'canceled', stripe_subscription_id: 'sub_history')
      capability = plan.actions.fetch(0).account_purge_context
      allow(org).to receive_messages(subscription_status: 'active', billing_live?: true)

      expect(capability.authorized_for?(org)).to be(false)
    end

    it 'invalidates an issued deletion capability when migration starts' do
      allow(org).to receive(:migration_status).and_return('completed')
      capability = plan.actions.fetch(0).account_purge_context
      allow(org).to receive(:migration_status).and_return('migrating')

      expect(capability.authorized_for?(org)).to be(false)
    end
  end

  it 'does not read the global registries on the shallow request path' do
    org = organization
    owner_membership = membership(
      org_objid: org.objid,
      customer_objid: customer.objid,
      role: 'owner',
    )
    allow(customer).to receive(:participations)
      .and_return(collection(["organization:#{org.objid}:members"]))
    allow(customer).to receive(:organization_instances).and_return(collection([org]))
    stub_membership_lookup(org, customer.objid => owner_membership)
    allow(Onetime::Organization).to receive(:load).with(org.objid).and_return(org)
    allow(Onetime::Customer).to receive(:load).with(customer.objid).and_return(customer)
    allow(contact_index).to receive(:get).with('target@example.com').and_return(org.objid)

    expect(instances).not_to receive(:each)
    expect(membership_instances).not_to receive(:each)
    expect(domain_instances).not_to receive(:each)

    expect(described_class.new(customer: customer).call).to be_executable
  end

  describe 'default_org_id' do
    let(:org) { organization }
    let(:owner_membership) do
      membership(org_objid: org.objid, customer_objid: customer.objid, role: 'owner')
    end
    let(:admin) { double('Customer', objid: 'cust-admin') }
    let(:admin_membership) do
      membership(org_objid: 'org-tenant', customer_objid: admin.objid, role: 'owner')
    end

    # A custom-domain organization owned by someone else. It carries
    # is_default because it is its owner's own default workspace.
    def tenant_org(member_ids)
      organization(
        objid: 'org-tenant',
        extid: 'on_tenant',
        owner_id: admin.objid,
        created_by: admin.objid,
        contact_email: 'admin@tenant.example',
        members: collection(member_ids),
      )
    end

    def stub_workspace(default_org_id:, participating: [org])
      allow(customer).to receive(:default_org_id).and_return(default_org_id)
      allow(customer).to receive(:participations)
        .and_return(collection(participating.map { |each_org| "organization:#{each_org.objid}:members" }))
      allow(customer).to receive(:organization_instances).and_return(collection(participating))
      stub_membership_lookup(org, customer.objid => owner_membership)
      allow(Onetime::Organization).to receive(:load).with(org.objid).and_return(org)
      allow(Onetime::Customer).to receive(:load).with(customer.objid).and_return(customer)
      allow(Onetime::Customer).to receive(:load).with(admin.objid).and_return(admin)
      allow(contact_index).to receive(:get).with('target@example.com').and_return(org.objid)
      allow(contact_index).to receive(:get).with('admin@tenant.example').and_return('org-tenant')
    end

    it 'blocks when it names a second default workspace the customer owns' do
      other = organization(objid: 'org-other', extid: 'on_other')
      stub_workspace(default_org_id: other.objid)
      allow(Onetime::Organization).to receive(:load).with(other.objid).and_return(other)
      stub_membership_lookup(
        other,
        customer.objid => membership(org_objid: other.objid, customer_objid: customer.objid, role: 'owner'),
      )

      plan = described_class.new(customer: customer).call

      expect(plan).not_to be_executable
      expect(plan.blockers).to include(code: :default_workspace_mismatch, org_id: 'on_personal')
    end

    # SSO sign-in on a custom domain points default_org_id at the tenant
    # organization it joins (JoinDomainOrganization#adopt_domain_default_org).
    it 'plans the purge when it names a tenant organization the customer belongs to' do
      tenant = tenant_org([admin.objid, customer.objid])
      stub_workspace(default_org_id: tenant.objid, participating: [org, tenant])
      allow(Onetime::Organization).to receive(:load).with(tenant.objid).and_return(tenant)
      stub_membership_lookup(
        tenant,
        admin.objid => admin_membership,
        customer.objid => membership(org_objid: tenant.objid, customer_objid: customer.objid, role: 'member'),
      )

      plan = described_class.new(customer: customer).call

      expect(plan.blockers).to be_empty
      expect(plan.actions.map { |action| [action.type, action.org_id] })
        .to contain_exactly([:delete_organization, 'on_personal'], [:remove_membership, 'on_tenant'])
    end

    it 'plans the purge when it names an organization the customer was removed from (#4860)' do
      tenant = tenant_org([admin.objid])
      stub_workspace(default_org_id: tenant.objid)
      allow(Onetime::Organization).to receive(:load).with(tenant.objid).and_return(tenant)
      stub_membership_lookup(tenant, admin.objid => admin_membership)

      plan = described_class.new(customer: customer).call

      expect(plan.blockers).to be_empty
      expect(plan.actions.map { |action| [action.type, action.org_id] })
        .to eq([[:delete_organization, 'on_personal']])
    end

    it 'plans the purge when it names an organization that no longer exists' do
      stub_workspace(default_org_id: 'org-gone')

      plan = described_class.new(customer: customer).call

      expect(plan.blockers).to be_empty
      expect(plan.actions.map(&:type)).to eq([:delete_organization])
    end
  end

  it 'blocks a domain whose org_id references the workspace despite missing domain indexes' do
    org = organization
    owner_membership = membership(
      org_objid: org.objid,
      customer_objid: customer.objid,
      role: 'owner',
    )
    domain = double('Domain', objid: 'domain-drifted', org_id: org.objid)
    allow(customer).to receive(:participations)
      .and_return(collection(["organization:#{org.objid}:members"]))
    allow(customer).to receive(:organization_instances).and_return(collection([org]))
    stub_organization_scan(org)
    stub_membership_scan(owner_membership)
    stub_domain_scan(domain)
    stub_membership_lookup(org, customer.objid => owner_membership)
    allow(Onetime::Customer).to receive(:load).with(customer.objid).and_return(customer)
    allow(contact_index).to receive(:get).with('target@example.com').and_return(org.objid)

    sweep = registry_sweep(organizations: [org], memberships: [owner_membership], domains: [domain])
    plan  = described_class.new(customer: customer, deep: true, registry_sweep: sweep).call

    expect(plan).not_to be_executable
    expect(plan.blockers).to include(hash_including(code: :drifted_domains))
  end

  it 'blocks an unrelated organization holding the normalized customer email' do
    owner = double('Owner', objid: 'cust-owner')
    org = organization(
      objid: 'org-foreign',
      extid: 'on_foreign',
      owner_id: owner.objid,
      created_by: owner.objid,
      contact_email: 'target@example.com',
      is_default: 'false',
      members: collection([owner.objid]),
    )
    owner_membership = membership(
      org_objid: org.objid,
      customer_objid: owner.objid,
      role: 'owner',
    )

    stub_organization_scan(org)
    stub_membership_scan(owner_membership)
    stub_membership_lookup(org, customer.objid => nil, owner.objid => owner_membership)
    allow(Onetime::Customer).to receive(:load).with(owner.objid).and_return(owner)
    allow(contact_index).to receive(:get).with('target@example.com').and_return(org.objid)

    plan = described_class.new(customer: customer).call

    expect(plan).not_to be_executable
    expect(plan.blockers).to include(hash_including(code: :contact_email_collision, org_id: 'on_foreign'))
  end

  it 'asks the contact-email finder for every spelling and refuses two holders' do
    org              = organization
    owner_membership = membership(
      org_objid: org.objid,
      customer_objid: customer.objid,
      role: 'owner',
    )
    allow(customer).to receive(:participations)
      .and_return(collection(["organization:#{org.objid}:members"]))
    allow(customer).to receive(:organization_instances).and_return(collection([org]))
    stub_organization_scan(org)
    stub_membership_scan(owner_membership)
    stub_membership_lookup(org, customer.objid => owner_membership)
    allow(Onetime::Customer).to receive(:load).with(customer.objid).and_return(customer)
    allow(contact_index).to receive(:get).with('target@example.com').and_return(org.objid)
    # An exact hit exists, and a second spelling is held by ANOTHER organization.
    # Only an exhaustive probe can see it.
    allow(Onetime::Organization).to receive(:find_contact_email_claims)
      .with('target@example.com', exhaustive: true)
      .and_return('target@example.com' => org.objid, 'Target@Example.com' => 'org-other')

    plan = described_class.new(customer: customer).call

    expect(plan).not_to be_executable
    expect(plan.blockers).to include(hash_including(code: :contact_email_index_ambiguous, holder_count: 2))
  end

  it 'sees a live membership the organization member set lost when given a registry snapshot' do
    org               = organization
    owner_membership  = membership(
      org_objid: org.objid,
      customer_objid: customer.objid,
      role: 'owner',
    )
    # An ACTIVE row for another customer whose id is absent from org.members:
    # shallow discovery derives rows from that set, so without the snapshot the
    # workspace reads as sole-owned and is planned for deletion.
    hidden_membership = membership(
      org_objid: org.objid,
      customer_objid: 'cust-hidden',
      role: 'member',
    )
    allow(customer).to receive(:participations)
      .and_return(collection(["organization:#{org.objid}:members"]))
    allow(customer).to receive(:organization_instances).and_return(collection([org]))
    stub_organization_scan(org)
    stub_membership_lookup(org, customer.objid => owner_membership)
    allow(Onetime::OrganizationMembership).to receive(:load)
      .with(hidden_membership.objid).and_return(hidden_membership)
    allow(Onetime::Customer).to receive(:load).with(customer.objid).and_return(customer)
    allow(Onetime::Customer).to receive(:load).with('cust-hidden').and_return(double('Customer'))
    allow(contact_index).to receive(:get).with('target@example.com').and_return(org.objid)

    expect(described_class.new(customer: customer).call).to be_executable

    snapshot = Auth::Operations::Customers::MembershipSnapshot.new(
      org.objid => [owner_membership.objid, hidden_membership.objid],
    )
    plan = described_class.new(customer: customer, membership_snapshot: snapshot).call

    expect(plan).not_to be_executable
    expect(plan.blockers.map { |blocker| blocker[:code] }).to include(:membership_index_drift)
    expect(plan.actions).to be_empty
  end

  it 'skips a snapshot row that no longer loads instead of reporting drift' do
    org              = organization
    owner_membership = membership(
      org_objid: org.objid,
      customer_objid: customer.objid,
      role: 'owner',
    )
    allow(customer).to receive(:participations)
      .and_return(collection(["organization:#{org.objid}:members"]))
    allow(customer).to receive(:organization_instances).and_return(collection([org]))
    stub_organization_scan(org)
    stub_membership_lookup(org, customer.objid => owner_membership)
    allow(Onetime::Customer).to receive(:load).with(customer.objid).and_return(customer)
    allow(contact_index).to receive(:get).with('target@example.com').and_return(org.objid)

    # Removed by an earlier candidate of the same bulk run: the snapshot still
    # names it, the registry no longer has it.
    snapshot = Auth::Operations::Customers::MembershipSnapshot.new(
      org.objid => [owner_membership.objid, 'organization:org-personal:customer:cust-gone:org_membership'],
    )
    plan = described_class.new(customer: customer, membership_snapshot: snapshot).call

    expect(plan).to be_executable
    expect(plan.actions.map(&:type)).to eq([:delete_organization])
    expect(Onetime::OrganizationMembership).to have_received(:load)
      .with('organization:org-personal:customer:cust-gone:org_membership')
  end

  it 'blocks when organization discovery is incomplete' do
    allow(customer).to receive(:participations).and_raise(Familia::Problem, 'unavailable')
    allow(instances).to receive(:each).and_raise(Familia::Problem, 'unavailable')
    allow(membership_instances).to receive(:each).and_raise(Familia::Problem, 'unavailable')
    allow(domain_instances).to receive(:each).and_raise(Familia::Problem, 'unavailable')
    allow(contact_index).to receive(:get).and_raise(Familia::Problem, 'unavailable')

    plan = described_class.new(customer: customer, deep: true).call

    expect(plan).not_to be_executable
    expect(plan.blockers.map { |blocker| blocker[:code] }).to contain_exactly(
      :participation_lookup_failed,
      :membership_scan_failed,
      :organization_scan_failed,
      :contact_email_lookup_failed,
      :domain_scan_failed,
    )
  end
end
