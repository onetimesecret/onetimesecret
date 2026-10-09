# spec/unit/onetime/models/membership_snapshot_invalidation_spec.rb
#
# frozen_string_literal: true

# A request's Onetime::MembershipSnapshot is dropped by the model writes that
# change what it reflects: the Familia-generated membership writers on
# Organization, archive!/unarchive!, and Customer#default_org_id=. Real
# datastore: the hooks wrap generated methods, so a double would not prove
# that `super` reaches them.
#
# Run: tests/lanes/run unit --only spec/unit/onetime/models/membership_snapshot_invalidation_spec.rb
require 'spec_helper'

RSpec.describe 'MembershipSnapshot invalidation', :datastore do
  let(:suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }
  let(:snapshot) { Onetime::MembershipSnapshot }

  before do
    @customers = []
    @orgs      = []
    @owner     = track_customer(Onetime::Customer.create!(email: "snap_owner_#{suffix}@onetimesecret.com"))
    @member    = track_customer(Onetime::Customer.create!(email: "snap_member_#{suffix}@onetimesecret.com"))
    @org       = track_org(Onetime::Organization.create!("Snap #{suffix}", @owner, is_default: true))
    snapshot.open
  end

  after do
    snapshot.close
    @orgs.each { |org| org.destroy! rescue nil } # rubocop:disable Style/RescueModifier
    @customers.each { |cust| cust.destroy! rescue nil } # rubocop:disable Style/RescueModifier
  end

  def track_customer(cust)
    @customers << cust
    cust
  end

  def track_org(org)
    @orgs << org
    org
  end

  it 'is dropped for a customer added to an organization' do
    before_add = snapshot.for(@member)
    expect(before_add.organizations).to eq([])

    @org.add_members_instance(@member, through_attrs: { role: 'member', status: 'active' })

    expect(snapshot.for(@member)).not_to be(before_add)
    expect(snapshot.for(@member).organizations.map(&:objid)).to eq([@org.objid])
  end

  it 'is dropped for a customer removed from an organization' do
    @org.add_members_instance(@member, through_attrs: { role: 'member', status: 'active' })
    before_remove = snapshot.for(@member)
    expect(before_remove.organizations.map(&:objid)).to eq([@org.objid])

    @org.remove_members_instance(@member)

    expect(snapshot.for(@member)).not_to be(before_remove)
    expect(snapshot.for(@member).organizations).to eq([])
  end

  it 'is dropped for a customer whose invitation is activated' do
    invitation    = Onetime::OrganizationMembership.create_invitation!(
      organization: @org, email: @member.email, inviter: @owner, role: 'member',
    )
    before_accept = snapshot.for(@member)
    expect(before_accept.organizations).to eq([])

    invitation.accept!(@member)

    expect(snapshot.for(@member)).not_to be(before_accept)
    expect(snapshot.for(@member).organizations.map(&:objid)).to eq([@org.objid])
  end

  it 'is dropped for every customer when the organization is archived or unarchived' do
    owner_before  = snapshot.for(@owner)
    member_before = snapshot.for(@member)

    @org.archive!
    expect(snapshot.for(@owner)).not_to be(owner_before)
    expect(snapshot.for(@member)).not_to be(member_before)

    owner_archived = snapshot.for(@owner)
    @org.unarchive!
    expect(snapshot.for(@owner)).not_to be(owner_archived)
  end

  it 'is dropped when a changed default preference is saved' do
    loader = Onetime::Application::OrganizationLoader
    other  = track_org(Onetime::Organization.create!("Other #{suffix}", @owner))
    expect(loader.default_organization(@owner).objid).to eq(@org.objid)

    @owner.default_org_id = other.objid
    @owner.save

    expect(loader.default_organization(@owner).objid).to eq(other.objid)
  end

  it 'is dropped when the default preference is written directly' do
    loader = Onetime::Application::OrganizationLoader
    other  = track_org(Onetime::Organization.create!("Other #{suffix}", @owner))
    expect(loader.default_organization(@owner).objid).to eq(@org.objid)

    @owner.default_org_id!(other.objid)

    expect(loader.default_organization(@owner).objid).to eq(other.objid)
  end

  it 'survives a save that does not touch the preference, and a reload' do
    before_save = snapshot.for(@owner)

    @owner.verified = 'true'
    @owner.save
    Onetime::Customer.load(@owner.objid)

    expect(snapshot.for(@owner)).to be(before_save)
  end

  it 'is not dropped by an unrelated customer\'s membership change' do
    owner_before = snapshot.for(@owner)

    @org.add_members_instance(@member, through_attrs: { role: 'member', status: 'active' })

    expect(snapshot.for(@owner)).to be(owner_before)
  end
end
