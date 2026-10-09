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
