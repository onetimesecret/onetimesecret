# apps/web/auth/spec/operations/customers/registry_sweep_spec.rb
#
# frozen_string_literal: true

# The pipelined registry listing behind a deep purge preflight, against the
# real datastore: the keys it probes must be the keys the models write.
#
# Run: tests/lanes/run unit --only apps/web/auth/spec/operations/customers/registry_sweep_spec.rb

require 'spec_helper'
require 'auth/operations/customers/registry_sweep'

RSpec.describe Auth::Operations::Customers::RegistrySweep, :datastore do
  let(:suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }
  let(:membership_class) { Onetime::OrganizationMembership }

  before do
    @customers = []
    @orgs      = []
    @rows      = []
    @domains   = []
    @owner     = track(@customers, Onetime::Customer.create!(email: "sweep_owner_#{suffix}@onetimesecret.com"))
    @target    = track(@customers, Onetime::Customer.create!(email: "sweep_target_#{suffix}@onetimesecret.com"))
    @bystander = track(@customers, Onetime::Customer.create!(email: "sweep_other_#{suffix}@onetimesecret.com"))

    # Referenced through owner_id and members.
    @owned  = track(@orgs, Onetime::Organization.create!("Owned #{suffix}", @target, is_default: true))
    # Referenced through members and the target's composite row.
    @shared = track(@orgs, Onetime::Organization.create!("Shared #{suffix}", @owner))
    @shared.add_members_instance(@target, through_attrs: { role: 'member', status: 'active' })
    # Not referenced at all.
    @other  = track(@orgs, Onetime::Organization.create!("Other #{suffix}", @bystander))
    # Referenced only by an active composite row that the members set lost.
    @row_only = track(@orgs, Onetime::Organization.create!("RowOnly #{suffix}", @bystander))
    @drifted_row = track(@rows, membership_class.new(
      objid: membership_class.composite_objid(@row_only.objid, @target.objid),
      organization_objid: @row_only.objid,
      customer_objid: @target.objid,
      role: 'member',
      status: 'active',
    ))
    @drifted_row.save
    # A staged row with a generated objid: its organization is known only
    # from the hash, never from the identifier.
    @staged_row = track(@rows, membership_class.new(
      organization_objid: @other.objid,
      customer_objid: @target.objid,
      role: 'member',
      status: 'pending',
      invited_email: @target.email,
    ))
    @staged_row.save
  end

  after do
    @domains.each do |domain|
      fqdn = domain.display_domain
      domain.destroy! if domain.exists?
      Onetime::CustomDomain.display_domain_index.remove(fqdn)
    end
    @rows.each { |row| row.destroy! if row.exists? }
    @orgs.each { |org| org.destroy! if org.exists? }
    @customers.each { |cust| cust.destroy! if cust.exists? }
  rescue StandardError => ex
    warn "[registry sweep spec] cleanup failed: #{ex.class}: #{ex.message}"
  end

  def track(list, record)
    list << record
    record
  end

  def capture
    described_class.capture(customer_objid: @target.objid)
  end

  it 'probes the keys the models write' do
    expect(Onetime::Organization.dbkey(@shared.objid, :members)).to eq(@shared.members.dbkey)
    expect(membership_class.dbkey(@drifted_row.objid)).to eq(@drifted_row.dbkey)
    expect(Onetime::CustomDomain.dbkey('x')).to eq(Onetime::CustomDomain.new(objid: 'x').dbkey)
  end

  it 'lists every organization and names the ones that reference the target' do
    sweep = capture

    expect(sweep.failures).to be_empty
    expect(sweep.organization_ids).to include(@owned.objid, @shared.objid, @other.objid, @row_only.objid)
    expect(sweep.referenced_org_ids).to include(@owned.objid, @shared.objid, @row_only.objid)
    expect(sweep.referenced_org_ids).not_to include(@other.objid)
  end

  it 'groups membership rows by organization and names the rows that belong to the target' do
    sweep = capture

    owner_row  = membership_class.composite_objid(@shared.objid, @owner.objid)
    target_row = membership_class.composite_objid(@shared.objid, @target.objid)
    expect(sweep.membership_objids_for(@shared.objid)).to contain_exactly(owner_row, target_row)
    expect(sweep.membership_objids_for(@other.objid)).to include(@staged_row.objid)
    expect(sweep.target_membership_objids).to include(
      membership_class.composite_objid(@owned.objid, @target.objid),
      target_row,
      @drifted_row.objid,
      @staged_row.objid,
    )
    expect(sweep.target_membership_objids).not_to include(owner_row)
    expect(sweep.membership_ids).to include(owner_row, target_row, @drifted_row.objid, @staged_row.objid)
  end

  it 'groups custom domains by the organization their org_id names' do
    domain = track(@domains, Onetime::CustomDomain.create!("sweep-#{suffix.tr('_', '-')}.example.com", @owned.objid))

    sweep = capture

    expect(sweep.domain_ids).to include(domain.objid)
    expect(sweep.domain_objids_for(@owned.objid)).to eq([domain.objid])
    expect(sweep.domain_objids_for(@other.objid)).to be_empty
  end

  describe '#refreshed' do
    it 'probes only identifiers the previous sweep did not list and keeps its results' do
      known = described_class.new(
        customer_objid: @target.objid,
        organization_ids: Onetime::Organization.instances.to_a.map(&:to_s),
        referenced_org_ids: ['org-carried-over'],
        membership_ids: membership_class.instances.to_a.map(&:to_s),
        membership_objids_by_org: { 'org-carried-over' => ['row-carried-over'] },
        target_membership_objids: ['row-carried-over'],
      )
      late = track(@orgs, Onetime::Organization.create!("Late #{suffix}", @target))

      sweep = known.refreshed

      expect(sweep.referenced_org_ids).to include('org-carried-over', late.objid)
      # Listed by the previous sweep, so not probed again: a reference it did
      # not record stays unrecorded until a full capture.
      expect(sweep.referenced_org_ids).not_to include(@owned.objid)
      expect(sweep.organization_ids).to include(@owned.objid, late.objid)
      expect(sweep.membership_objids_for('org-carried-over')).to eq(['row-carried-over'])
      expect(sweep.membership_objids_for(late.objid))
        .to eq([membership_class.composite_objid(late.objid, @target.objid)])
      expect(sweep.target_membership_objids).to include('row-carried-over', membership_class.composite_objid(late.objid, @target.objid))
    end

    it 'reprobes a registry the previous sweep failed to list' do
      failed = described_class.new(
        customer_objid: @target.objid,
        organization_ids: [@owned.objid],
        failures: { organizations: 'IOError' },
      )

      sweep = failed.refreshed

      expect(sweep.failures).to be_empty
      expect(sweep.referenced_org_ids).to include(@owned.objid)
    end
  end

  it 'records a registry that cannot be listed and keeps the others' do
    broken = double('CustomDomain.instances')
    allow(broken).to receive(:each).and_raise(IOError)
    allow(Onetime::CustomDomain).to receive(:instances).and_return(broken)

    sweep = capture

    expect(sweep.failures).to eq(domains: 'IOError')
    expect(sweep).to be_failed(:domains)
    expect(sweep).not_to be_failed(:organizations)
    expect(sweep.referenced_org_ids).to include(@owned.objid)
  end
end
