# spec/cli/org_doctor_owner_repair_collision_spec.rb
#
# frozen_string_literal: true

# `organizations doctor --repair`, check 1 (owner promotion) on an org that
# is ALSO in check 6's duplicate state: another org's unique-index entry holds
# a value this org carries. A full `org.save` guards every unique index and
# raises Familia::RecordExistsError there, which used to abort the whole
# --all scan with no report. The promotion must write only its own fields,
# and a failed promotion must be recorded on the issue while the scan goes on.
#
# Real datastore, not `type: :cli` (that lane's before-hook mocks
# Familia.dbclient) — same rationale as org_doctor_command_spec.rb.
#
# Run: tests/lanes/run unit --only spec/cli/org_doctor_owner_repair_collision_spec.rb

require_relative 'cli_spec_helper'

RSpec.describe 'Org Doctor Command owner repair under an index collision' do
  describe 'real datastore', :datastore do
    let(:suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }
    let(:command) { Onetime::CLI::OrgDoctorCommand.new }
    let(:report) { { checked: 0, healthy: 0, issues: [], repaired: [] } }

    before do
      @customers = []
      @orgs      = []
    end

    after do
      @orgs.each do |org|
        @customers.each do |cust|
          membership = Onetime::OrganizationMembership.find_by_org_customer(org.objid, cust.objid)
          membership.destroy! if membership.respond_to?(:exists?) && membership.exists?
        end
        org.destroy! if org.exists?
      rescue StandardError => ex
        warn "[org doctor collision spec] org cleanup failed: #{ex.class}: #{ex.message}"
      end
      @customers.each do |cust|
        cust.destroy! if cust.exists?
      rescue StandardError => ex
        warn "[org doctor collision spec] customer cleanup failed: #{ex.class}: #{ex.message}"
      end
    end

    def create_org(label)
      owner = Onetime::Customer.create!(email: "doctor_#{label}_#{suffix}@onetimesecret.com")
      @customers << owner
      org = Onetime::Organization.create!("Doctor #{label} #{suffix}", owner)
      @orgs << org
      [org, owner]
    end

    # owner_id removed from the stored hash; the creator keeps its
    # role:'owner' membership, so check 1 has a candidate to promote.
    def blank_owner_id(org)
      org.owner_id = nil
      org.save_fields(:owner_id)
    end

    # The org carries a stripe_customer_id whose index entry names ANOTHER
    # org (check 6's duplicate state). Written straight to the hash: the
    # model refuses to create this state, the doctor exists to find it.
    def collide_stripe_customer_id(holder, carrier)
      value = "cus_dup_#{suffix}"
      holder.stripe_customer_id = value
      holder.save_fields(:stripe_customer_id)
      carrier.dbclient.hset(carrier.dbkey, 'stripe_customer_id', carrier.serialize_value(value))
      value
    end

    # Mirrors `call` for an --all run over exactly these orgs.
    def scan(orgs)
      command.send(:index_unique_index_claims, orgs)
      command.instance_variable_set(:@index_claims_complete, true)
      orgs.each { |org| command.send(:check_org, org, report, repair: true) }
    end

    def owner_issue_for(org)
      group = report[:issues].find { |g| g[:org_objid] == org.objid }
      group && group[:issues].find { |i| i[:check] == :owner_exists }
    end

    it 'promotes the owner with a field-scoped write that a full save would refuse' do
      holder, = create_org('holder')
      carrier, carrier_owner = create_org('carrier')
      blank_owner_id(carrier)
      collide_stripe_customer_id(holder, carrier)

      carrier = Onetime::Organization.load(carrier.objid)
      expect(carrier.owner_id.to_s).to be_empty

      # Discriminating fixture: a full save of this org raises.
      expect { Onetime::Organization.load(carrier.objid).save }.to raise_error(Familia::RecordExistsError)

      expect { scan([carrier, holder]) }.not_to raise_error

      expect(report[:checked]).to eq(2)
      reloaded = Onetime::Organization.load(carrier.objid)
      expect(reloaded.owner_id).to eq(carrier_owner.objid)
      expect(report[:repaired]).to include(
        a_hash_including(org: carrier.extid, action: :owner_promoted, new_owner_extid: carrier_owner.extid),
      )
      expect(owner_issue_for(carrier)).not_to have_key(:repair_failed)
      # The collision itself is still reported (check 6), not papered over.
      carrier_group = report[:issues].find { |g| g[:org_objid] == carrier.objid }
      expect(carrier_group[:issues].map { |i| i[:check] }).to include(:stripe_customer_id_index)
    end

    it 'records a failed promotion on the issue and keeps scanning' do
      broken, = create_org('broken')
      healthy, = create_org('healthy')
      blank_owner_id(broken)
      broken = Onetime::Organization.load(broken.objid)

      allow(broken).to receive(:save_fields)
        .and_raise(Familia::RecordExistsError.new('organization:x', existing_id: 'other-objid'))

      expect { scan([broken, healthy]) }.not_to raise_error

      expect(report[:checked]).to eq(2)
      expect(report[:healthy]).to eq(1)
      issue = owner_issue_for(broken)
      expect(issue[:repair_failed]).to eq('unique-index conflict with other-objid')
      expect(issue[:repair_action]).to eq('Repair failed: unique-index conflict with other-objid')
      expect(report[:repaired]).to be_empty

      # In-memory state put back: later checks read what is stored.
      expect(broken.owner_id.to_s).to be_empty
      expect(Onetime::Organization.load(broken.objid).owner_id.to_s).to be_empty

      # Nothing repaired, a repairable issue left: exit 1, as before.
      expect { command.exit_with_status(report, repair: true) }
        .to raise_error(SystemExit) { |ex| expect(ex.status).to eq(1) }
    end
  end
end
