# spec/cli/org_doctor_command_spec.rb
#
# frozen_string_literal: true

# Covers the `bin/ots org doctor --repair` owner-promotion path (#3907):
# owner_id is repaired into objid space, and created_by follows ONLY when the
# stored value is the promoted owner's own legacy identity (custid/email).
# A different person's created_by is transfer-style audit state (D32) and must
# survive the repair untouched.
#
# Lives in its own file rather than org_command_spec.rb: these examples need a
# REAL datastore (the candidate search walks the members sorted set and the
# membership through-model, which mocks satisfy vacuously — same rationale as
# spec/support/helpers/org_doctor_invariants.rb), while org_command_spec.rb is
# the mocked arg/output surface.
#
# The examples drive check_owner_exists directly (via #send) instead of the
# full CLI `call`: the repair semantics are the unit under test; argument
# parsing, boot, and output rendering are covered elsewhere.
#
# Deliberately NOT `type: :cli`: that lane's before-hook (cli_spec_helper.rb)
# mocks Familia.dbclient and stubs Customer.instances with doubles, which
# would sever these examples from the datastore they exist to hit.
#
# Fixtures are DISCRIMINATING on purpose: a fresh customer has custid == objid
# (Customer#init defaults custid ||= objid), so only an owner whose custid
# diverged — the legacy v1 email-custid shape — can tell objid writes apart
# from custid writes. Same pattern as the unit create spec.
#
# Run: bundle exec rspec spec/cli/org_doctor_command_spec.rb

require_relative 'cli_spec_helper'

RSpec.describe 'Org Doctor Command owner repair' do
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
        warn "[org doctor spec] org cleanup failed: #{ex.class}: #{ex.message}"
      end
      @customers.each do |cust|
        cust.destroy! if cust.exists?
      rescue StandardError => ex
        warn "[org doctor spec] customer cleanup failed: #{ex.class}: #{ex.message}"
      end
    end

    def track_customer(cust)
      @customers << cust
      cust
    end

    # A customer in the legacy v1 shape: custid diverged from objid to the
    # email. This is the only shape that can distinguish objid writes from
    # custid writes.
    def create_legacy_customer(email)
      cust        = track_customer(Onetime::Customer.create!(email: email))
      cust.custid = cust.email
      cust.save
      cust
    end

    # An org in the legacy on-disk shape: BOTH audit fields hold the creator's
    # email-shaped custid (owner_id == created_by == email, chore Branch 1 —
    # consistent but in the wrong space). Customer.load(email) misses, so
    # doctor check 1 fires and the repair path engages.
    def break_org_to_legacy_shape(org, creator)
      org.owner_id   = creator.custid
      org.created_by = creator.custid
      org.save
      org
    end

    def run_owner_repair(org)
      issues = []
      command.send(:check_owner_exists, org, issues, report, repair: true)
      issues
    end

    it 'migrates BOTH owner_id and created_by to objid when the promoted owner IS the creator' do
      legacy = create_legacy_customer("doctor_same_#{suffix}@onetimesecret.com")
      org    = Onetime::Organization.create!("Doctor Same #{suffix}", legacy)
      @orgs << org
      break_org_to_legacy_shape(org, legacy)

      run_owner_repair(org)

      # Assert on a FRESH load: an in-memory setter can mask a failed save.
      reloaded = Onetime::Organization.load(org.objid)
      expect(reloaded.owner_id).to eq(legacy.objid)
      expect(reloaded.owner_id).not_to eq(legacy.custid)
      expect(reloaded.created_by).to eq(legacy.objid)
      expect(reloaded.created_by).to eq(reloaded.owner_id) # chore Branch 1

      expect(report[:repaired].size).to eq(1)
      expect(report[:repaired].first).to include(
        action: :owner_promoted,
        created_by_migrated: true,
      )
    end

    it 'repairs owner_id but leaves a DIFFERENT person\'s created_by untouched (D32)' do
      creator  = create_legacy_customer("doctor_creator_#{suffix}@onetimesecret.com")
      promotee = track_customer(
        Onetime::Customer.create!(email: "doctor_promotee_#{suffix}@onetimesecret.com"),
      )
      creator_email = creator.custid

      org = Onetime::Organization.create!("Doctor Diff #{suffix}", creator)
      @orgs << org
      Onetime::OrganizationMembership.ensure_membership(org, promotee, role: 'owner')
      break_org_to_legacy_shape(org, creator)

      # The creator is gone — that is WHY check 1 fails and why the only
      # eligible candidate is a different person.
      creator.destroy!

      run_owner_repair(org)

      reloaded = Onetime::Organization.load(org.objid)
      expect(reloaded.owner_id).to eq(promotee.objid)
      # Audit state preserved: created_by still names the (deleted) creator.
      expect(reloaded.created_by).to eq(creator_email)

      expect(report[:repaired].size).to eq(1)
      expect(report[:repaired].first).to include(
        action: :owner_promoted,
        created_by_migrated: false,
      )
    end

    it 'does not rewrite a created_by already in objid space (no-op migration)' do
      legacy = create_legacy_customer("doctor_objid_#{suffix}@onetimesecret.com")
      org    = Onetime::Organization.create!("Doctor Objid #{suffix}", legacy)
      @orgs << org
      # owner_id broken to the email, but created_by already correct.
      org.owner_id = legacy.custid
      org.save

      run_owner_repair(org)

      reloaded = Onetime::Organization.load(org.objid)
      expect(reloaded.owner_id).to eq(legacy.objid)
      expect(reloaded.created_by).to eq(legacy.objid)
      expect(report[:repaired].first).to include(created_by_migrated: false)
    end
  end
end
