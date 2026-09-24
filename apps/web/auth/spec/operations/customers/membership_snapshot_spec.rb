# apps/web/auth/spec/operations/customers/membership_snapshot_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'auth/operations/customers/membership_snapshot'

RSpec.describe Auth::Operations::Customers::MembershipSnapshot do
  let(:registry) { double('OrganizationMembership.instances') }

  before do
    allow(Onetime::OrganizationMembership).to receive(:instances).and_return(registry)
    allow(Onetime::OrganizationMembership).to receive(:load).and_return(nil)
  end

  def stub_registry(objids)
    allow(registry).to receive(:each) { |&block| objids.each { |objid| block.call(objid) } }
  end

  it 'groups composite objids by organization without loading a row' do
    stub_registry(
      [
        'organization:org-a:customer:cust-1:org_membership',
        'organization:org-a:customer:cust-2:org_membership',
        'organization:org-b:customer:cust-1:org_membership',
      ],
    )

    snapshot = described_class.capture

    expect(snapshot.objids_for('org-a')).to contain_exactly(
      'organization:org-a:customer:cust-1:org_membership',
      'organization:org-a:customer:cust-2:org_membership',
    )
    expect(snapshot.objids_for('org-b')).to eq(['organization:org-b:customer:cust-1:org_membership'])
    expect(snapshot.objids_for('org-missing')).to eq([])
    expect(snapshot.size).to eq(3)
    expect(snapshot.organization_count).to eq(2)
    expect(Onetime::OrganizationMembership).not_to have_received(:load)
  end

  it 'loads a non-composite objid once to read its organization' do
    stub_registry(%w[invite-token-row unreadable-row])
    allow(Onetime::OrganizationMembership).to receive(:load).with('invite-token-row')
      .and_return(double('Membership', organization_objid: 'org-a'))

    snapshot = described_class.capture

    expect(snapshot.objids_for('org-a')).to eq(['invite-token-row'])
    expect(snapshot.size).to eq(1)
  end

  it 'is frozen and deduplicates' do
    snapshot = described_class.new('org-a' => %w[row-1 row-1 row-2])

    expect(snapshot).to be_frozen
    expect(snapshot.objids_for(:'org-a')).to eq(%w[row-1 row-2])
    expect(snapshot.objids_for('org-a')).to be_frozen
  end
end
