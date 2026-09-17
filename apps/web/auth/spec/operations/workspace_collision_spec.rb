# apps/web/auth/spec/operations/workspace_collision_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'auth/operations/workspace_collision'

RSpec.describe Auth::Operations::WorkspaceCollision do
  let(:email) { 'user@example.com' }
  let(:raw_client) { double('Redis', hget: 'org_1', hscan: ['0', []]) }
  let(:index) { double('contact_email_index', dbclient: raw_client, dbkey: 'organization:contact_email_index') }
  let(:members) { double('members', to_a: []) }
  let(:domains) { double('domains', to_a: []) }
  let(:invitations) { double('pending_invitations', to_a: []) }
  let(:receipts) { double('receipts', size: 0) }
  let(:customer) { double('Customer', objid: 'cust_current', extid: 'ur_current') }
  let(:membership) { nil }

  let(:organization) do
    double(
      'Organization',
      objid: 'org_1',
      extid: 'on_1',
      is_default: 'true',
      contact_email: email,
      owner_id: '',
      members: members,
      domains: domains,
      pending_invitations: invitations,
      receipts: receipts,
    )
  end

  before do
    allow(Onetime::Organization).to receive(:contact_email_index).and_return(index)
    # The index is keyed verbatim, so the holder is resolved through
    # Organization.find_contact_email_claims. Mirror its O(1) probe onto the same
    # backing double each example stubs via `hget`.
    allow(index).to receive(:get) { |key| raw_client.hget('organization:contact_email_index', key) }
    allow(Onetime::Organization).to receive(:instances).and_return([])
    allow(Onetime::Organization).to receive(:load).with('org_1').and_return(organization)
    allow(Onetime::Customer).to receive(:load).and_return(nil)
    allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer).and_return(membership)
    allow(Onetime::CustomDomain).to receive(:instances).and_return([])
  end

  def classify(current_customer: customer)
    described_class.new(email: email, customer: current_customer).call
  end

  it 'classifies a missing raw index field as clear' do
    allow(raw_client).to receive(:hget).and_return(nil)

    expect(classify.classification).to eq(:clear)
  end

  it 'classifies an index value whose organization is missing as phantom_index' do
    allow(Onetime::Organization).to receive(:load).with('org_1').and_return(nil)

    result = classify

    expect(result.classification).to eq(:phantom_index)
    expect(result.evidence).to include(index_read_independently: true, organization_found: false)
  end

  it 'classifies a live holder whose contact email differs as index_mismatch' do
    allow(organization).to receive(:contact_email).and_return('other@example.com')

    expect(classify.classification).to eq(:index_mismatch)
  end

  it 'classifies a valid default workspace already owned by the current customer' do
    allow(organization).to receive(:owner_id).and_return('cust_current')
    allow(members).to receive(:to_a).and_return(['cust_current'])
    allow(Onetime::Customer).to receive(:load).with('cust_current').and_return(customer)
    active_owner = double('Membership', active?: true, owner?: true)
    allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
      .with('org_1', 'cust_current').and_return(active_owner)

    expect(classify.classification).to eq(:current_valid_workspace)
  end

  it 'classifies an ownerless organization without members or retained data as empty_orphan' do
    result = classify(current_customer: nil)

    expect(result.classification).to eq(:empty_orphan)
    expect(result.evidence).to include(
      owner_alive: false,
      current_customer_in_members: false,
      live_member_ids: [],
      stale_member_ids: [],
      domain_ids: [],
      domain_drift: false,
      invitation_ids: [],
      receipt_count: 0,
      billing_markers: [],
    )
  end

  it 'classifies stale member references without treating cleanup as adoption authority' do
    allow(members).to receive(:to_a).and_return(['deleted_customer'])

    result = classify(current_customer: nil)

    expect(result.classification).to eq(:stale_members)
    expect(result.evidence[:stale_member_ids]).to eq(['deleted_customer'])
  end

  it 'classifies live owners or members separately from stale references' do
    live = double('Customer', extid: 'ur_live')
    allow(organization).to receive(:owner_id).and_return('cust_live')
    allow(Onetime::Customer).to receive(:load).with('cust_live').and_return(live)

    expect(classify(current_customer: nil).classification).to eq(:live_members)
  end

  it 'classifies receipts and other retained markers as retained_data' do
    allow(receipts).to receive(:size).and_return(2)

    result = classify(current_customer: nil)

    expect(result.classification).to eq(:retained_data)
    expect(result.evidence[:receipt_count]).to eq(2)
  end

  it 'classifies incomplete evidence as unreadable rather than healthy' do
    allow(raw_client).to receive(:hget).and_raise(Redis::CommandError, 'NOAUTH')

    result = classify

    expect(result.classification).to eq(:unreadable)
    expect(result.to_h[:available]).to be(false)
    expect(result.evidence[:reason]).to eq('NOAUTH')
  end

  it 'does not repair a stale pointer when another live organization carries the address' do
    claimant = double('Claimant', objid: 'org_live', extid: 'on_live', contact_email: email)
    allow(Onetime::Organization).to receive(:instances).and_return(['org_live'])
    allow(Onetime::Organization).to receive(:load).with('org_live').and_return(claimant)
    allow(organization).to receive(:contact_email).and_return('other@example.com')

    result = classify

    expect(result.classification).to eq(:index_mismatch)
    expect(result.repairable_index_claim?).to be(false)
    expect(result.evidence[:contact_email_claimant_ids]).to eq(['org_live'])
  end

  it 'compare-and-deletes only against the exact raw value observed' do
    allow(Onetime::Organization).to receive(:load).with('org_1').and_return(nil)
    result = classify
    allow(raw_client).to receive(:eval).and_return(1)

    expect(described_class.compare_and_delete(result)).to be(true)
    expect(raw_client).to have_received(:eval).with(
      described_class::COMPARE_AND_DELETE_SCRIPT,
      keys: ['organization:contact_email_index'],
      argv: [email, 'org_1'],
    )
  end
end
