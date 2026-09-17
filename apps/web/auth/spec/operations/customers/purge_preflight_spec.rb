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
      default_org_id: 'org-personal',
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
    allow(Onetime::Organization).to receive(:contact_email_index).and_return(contact_index)
    allow(contact_index).to receive(:get).and_return(nil)
    # The index is keyed verbatim, so production resolves holders through these
    # two finders. Route them back at the `get` double each example stubs.
    allow(Onetime::Organization).to receive(:find_contact_email_claims) do |value|
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
      planid: 'free_v1',
      migration_status: nil,
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

  it 'discovers and plans a strict empty personal workspace from all agreeing indexes' do
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
    plan = described_class.new(customer: customer, deep: true).call

    expect(plan).not_to be_executable
    expect(plan.blockers.map { |blocker| blocker[:code] })
      .to include(:membership_index_drift, :target_membership_drift)
    expect(plan.actions).to be_empty
  end

  it 'fails closed on drift and billing state, not on the account own workspace content' do
    org = organization(
      members: collection([customer.objid, 'cust-stale']),
      domain_count: 1,
      pending_invitation_count: 1,
      pending_invitations: collection(['pending-1']),
      receipt_count: 2,
      stripe_customer_id: 'cus_retained',
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

  it 'blocks a default workspace that is not the target customer default' do
    org = organization
    owner_membership = membership(
      org_objid: org.objid,
      customer_objid: customer.objid,
      role: 'owner',
    )
    allow(customer).to receive(:default_org_id).and_return('org-other')
    allow(customer).to receive(:participations)
      .and_return(collection(["organization:#{org.objid}:members"]))
    allow(customer).to receive(:organization_instances).and_return(collection([org]))
    stub_organization_scan(org)
    stub_membership_scan(owner_membership)
    stub_membership_lookup(org, customer.objid => owner_membership)
    allow(Onetime::Customer).to receive(:load).with(customer.objid).and_return(customer)
    allow(contact_index).to receive(:get).with('target@example.com').and_return(org.objid)

    plan = described_class.new(customer: customer).call

    expect(plan).not_to be_executable
    expect(plan.blockers).to include(hash_including(code: :default_workspace_mismatch))
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

    plan = described_class.new(customer: customer, deep: true).call

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
