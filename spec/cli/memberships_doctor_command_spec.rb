# spec/cli/memberships_doctor_command_spec.rb
#
# frozen_string_literal: true

# Covers the `bin/ots memberships doctor --repair` removal of stale org.members
# entries (members whose customer record is gone).
#
# org.members is a Familia participation collection: it stores raw customer
# identifiers, and Familia sends a bare String argument JSON-quoted, so a
# `remove` given a String objid never matches an entry. A double for the
# collection cannot see that, so these examples use the real datastore.
#
# Deliberately NOT `type: :cli`: that hook (cli_spec_helper.rb) mocks
# Familia.dbclient. The examples drive check_stale_org_members directly, the
# same way org_doctor_command_spec.rb drives its checks.

require_relative 'cli_spec_helper'

RSpec.describe 'Memberships Doctor Command stale member repair', :datastore do
  let(:suffix) { "#{Familia.now.to_i}#{SecureRandom.hex(4)}" }
  let(:command) { Onetime::CLI::MembershipsDoctorCommand.new }
  let(:report) { { checked: 0, healthy: 0, issues: [], repaired: [] } }

  before do
    @customers = []
    @orgs      = []
  end

  after do
    @orgs.each do |org|
      org.destroy! if org.exists?
    rescue StandardError => ex
      warn "[memberships doctor spec] org cleanup failed: #{ex.class}: #{ex.message}"
    end
    @customers.each do |cust|
      cust.destroy! if cust.exists?
    rescue StandardError => ex
      warn "[memberships doctor spec] customer cleanup failed: #{ex.class}: #{ex.message}"
    end
  end

  def create_org(label)
    owner = Onetime::Customer.create!(email: "memberships_doctor_#{label}_#{suffix}@onetimesecret.com")
    @customers << owner
    org = Onetime::Organization.create!("Memberships Doctor #{label} #{suffix}", owner)
    @orgs << org
    org
  end

  # An org.members entry with no customer record behind it.
  def add_ghost_member(org)
    ghost = Onetime::Customer.new(objid: "ghost#{suffix}")
    org.members.add(ghost, Familia.now.to_f)
    expect(org.members.to_a).to include(ghost.objid)
    ghost
  end

  def run_stale_member_check(org, repair:)
    issues = []
    command.send(:check_stale_org_members, org, issues, report, repair: repair)
    issues
  end

  it 'reports a stale member and leaves it in place without --repair' do
    org   = create_org('report')
    ghost = add_ghost_member(org)

    issues = run_stale_member_check(org, repair: false)

    expect(issues.map { |i| i[:check] }).to eq([:stale_org_members])
    expect(issues.first[:stale_ids]).to eq([ghost.objid])
    expect(org.members.to_a).to include(ghost.objid)
    expect(report[:repaired]).to be_empty
  end

  it 'removes the stale member with --repair and counts it' do
    org   = create_org('repair')
    ghost = add_ghost_member(org)

    run_stale_member_check(org, repair: true)

    expect(org.members.to_a).not_to include(ghost.objid)
    # The real owner is untouched.
    expect(org.members.to_a).to include(@customers.first.objid)

    repaired = report[:repaired].select { |r| r[:action] == :stale_members_removed }
    expect(repaired.size).to eq(1)
    expect(repaired.first[:count]).to eq(1)
  end

  it 'counts only the entries it removed' do
    org   = create_org('raced')
    ghost = add_ghost_member(org)

    # Another process removes the entry after detection read it.
    allow(Onetime::Customer).to receive(:load).and_wrap_original do |original, objid|
      org.members.remove(ghost) if objid == ghost.objid
      original.call(objid)
    end

    issues = run_stale_member_check(org, repair: true)

    expect(issues.size).to eq(1)
    expect(report[:repaired]).to be_empty
  end
end
