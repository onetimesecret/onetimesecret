# spec/unit/onetime/operations/org/transfer_ownership_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Operations::Org::TransferOwnership (#3731).
#
# TWO LAYERS, on purpose:
#
#   1. Mocked contract (no datastore) — the guardrail statuses, the exactly-one
#      audit event, the negative "a refusal writes and audits NOTHING"
#      assertions, the rollback, and above all THE ORDER: promote -> pivot
#      owner_id -> demote. Memberships::SetRole is stubbed at its constructor so
#      the ordering is directly observable; it has its own coverage.
#
#   2. Real datastore (Valkey on 2121, see spec/config.test.yaml) — the
#      post-condition that actually matters: BOTH parties' entitlements are
#      re-materialized (the incoming owner GAINS manage_org, the outgoing owner
#      LOSES it) and the org still passes all five `bin/ots org doctor`
#      invariants, including check 4 which is `repairable: false`. None of that
#      is provable with mocks — materialization happens inside a Familia
#      through-model write. The five checks live in
#      spec/support/helpers/org_doctor_invariants.rb (`org_doctor_issues`),
#      shared with the org-create op's spec.
#
# Layer 2 registers every object it creates and destroys them in `after`. It
# NEVER flushes — the test datastore is shared.
#
# Run: bundle exec rspec spec/unit/onetime/operations/org/transfer_ownership_spec.rb

require 'spec_helper'
require 'onetime/models/admin_audit_event'
require 'onetime/operations/org/transfer_ownership'

RSpec.describe Onetime::Operations::Org::TransferOwnership do
  let(:actor) { 'ur_col_public_extid' } # PUBLIC identity (extid/email)

  describe 'mocked contract' do
    # Ordered log of every state-changing call the op makes, so the promote ->
    # owner_id -> demote sequence is asserted directly rather than inferred.
    let(:calls) { [] }

    let(:new_owner) do
      instance_double(
        Onetime::Customer,
        extid: 'ur_new_ext',
        objid: 'cust-obj-new',
        anonymous?: false,
      )
    end

    let(:old_owner) do
      instance_double(
        Onetime::Customer,
        extid: 'ur_old_ext',
        objid: 'cust-obj-old',
        anonymous?: false,
      )
    end

    let(:org) do
      instance_double(
        Onetime::Organization,
        extid: 'on_org_ext',
        objid: 'org-obj-1',
        owner_id: 'cust-obj-old',
        save: true,
      )
    end

    let(:target_membership) do
      instance_double(
        Onetime::OrganizationMembership,
        active?: true,
        owner?: false,
        customer_objid: 'cust-obj-new',
        customer: new_owner,
      )
    end

    let(:old_owner_membership) do
      instance_double(
        Onetime::OrganizationMembership,
        active?: true,
        owner?: true,
        customer_objid: 'cust-obj-old',
        customer: old_owner,
      )
    end

    def set_role_result(customer, from, to)
      Onetime::Operations::Memberships::SetRole::Result.new(
        status: :success,
        org_id: 'on_org_ext',
        customer_id: customer.extid,
        from: from,
        to: to,
      )
    end

    before do
      allow(Onetime::AdminAuditEvent).to receive(:record)
      allow(OT).to receive(:info)
      allow(OT).to receive(:le)

      allow(org).to receive(:owner_id=) { |value| calls << [:owner_id=, value] }

      allow(Onetime::OrganizationMembership)
        .to receive(:find_by_org_customer)
        .with('org-obj-1', 'cust-obj-new')
        .and_return(target_membership)
      allow(Onetime::OrganizationMembership)
        .to receive(:active_for_org)
        .with(org)
        .and_return([old_owner_membership, target_membership])
      allow(Onetime::Customer).to receive(:load).with('cust-obj-old').and_return(old_owner)

      # Record every SetRole construction in order, and hand back a success.
      allow(Onetime::Operations::Memberships::SetRole).to receive(:new) do |args|
        calls << [args[:customer].extid, args[:new_role]]
        instance_double(
          Onetime::Operations::Memberships::SetRole,
          call: set_role_result(args[:customer], args[:new_role] == 'owner' ? 'member' : 'owner', args[:new_role]),
        )
      end
    end

    def build(**overrides)
      described_class.new(
        **{ org: org, new_owner: new_owner, actor: actor, dry_run: false }.merge(overrides)
      )
    end

    describe 'ORDER — promote, pivot owner_id, demote' do
      # This is the single most important assertion in the file. SetRole refuses
      # to demote a sole owner (:last_owner), so a promote-after-demote
      # regression does not raise — it silently fails to transfer anything.
      it 'promotes the new owner BEFORE demoting the old one, pivoting owner_id between' do
        build.call

        expect(calls).to eq(
          [
            ['ur_new_ext', 'owner'],
            [:owner_id=, 'cust-obj-new'],
            ['ur_old_ext', 'admin'],
          ]
        )
      end

      it 'routes BOTH role changes through Memberships::SetRole (never a direct role=)' do
        build.call

        expect(Onetime::Operations::Memberships::SetRole).to have_received(:new).twice
        expect(Onetime::Operations::Memberships::SetRole).to have_received(:new)
          .with(hash_including(org: org, customer: new_owner, new_role: 'owner', actor: actor))
        expect(Onetime::Operations::Memberships::SetRole).to have_received(:new)
          .with(hash_including(org: org, customer: old_owner, new_role: 'admin', actor: actor))
      end
    end

    describe 'happy path' do
      it 'returns a fully populated :success Result' do
        result = build.call

        expect(result.status).to eq(:success)
        expect(result.org_id).to eq('on_org_ext')
        expect(result.from_owner_id).to eq('ur_old_ext')   # PUBLIC extid, never the objid
        expect(result.to_owner_id).to eq('ur_new_ext')
        expect(result.from_owner_role_after).to eq('admin')
        expect(result.demoted).to eq(['ur_old_ext'])
        expect(result.orphaned_owner).to be(false)
        expect(result.dry_run).to be(false)
      end

      it 'writes owner_id as the OBJID (D31 — what org doctor compares against) and saves' do
        build.call

        expect(org).to have_received(:owner_id=).with('cust-obj-new')
        expect(org).to have_received(:save)
      end

      it 'records EXACTLY ONE audit event from the op, public ids only' do
        build.call

        # The two composed SetRole calls emit their own 'membership.set_role'
        # events (D26 — three per transfer). They are stubbed here; the
        # real-datastore layer is where composition is exercised end to end.
        expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
          actor: actor,
          verb: 'organization.transfer_ownership',
          target: 'on_org_ext',
          result: :success,
          detail: { from: 'ur_old_ext', to: 'ur_new_ext', demoted_to: 'admin', demoted_count: 1 },
        )
      end

      it 'uses the full-noun audit verb the rest of the trail uses' do
        expect(described_class::AUDIT_VERB).to eq('organization.transfer_ownership')
      end

      it 'honours --demote-to member' do
        result = build(demote_to: 'member').call

        expect(calls.last).to eq(['ur_old_ext', 'member'])
        expect(result.from_owner_role_after).to eq('member')
      end

      it 'never touches created_by, contact_email or any billing field' do
        allow(org).to receive(:created_by=)
        allow(org).to receive(:contact_email=)
        allow(org).to receive(:billing_email=)
        allow(org).to receive(:stripe_customer_id=)

        build.call

        expect(org).not_to have_received(:created_by=)
        expect(org).not_to have_received(:contact_email=)
        expect(org).not_to have_received(:billing_email=)
        expect(org).not_to have_received(:stripe_customer_id=)
      end
    end

    describe 'dry run (the default)' do
      it 'defaults to dry_run: true — a destructive verb never applies by accident' do
        result = described_class.new(org: org, new_owner: new_owner, actor: actor).call

        expect(result.status).to eq(:planned)
        expect(result.dry_run).to be(true)
      end

      it 'plans the demotions and mutates + audits NOTHING' do
        result = build(dry_run: true).call

        expect(result.status).to eq(:planned)
        expect(result.demoted).to eq(['ur_old_ext'])
        expect(result.from_owner_id).to eq('ur_old_ext')
        expect(org).not_to have_received(:owner_id=)
        expect(org).not_to have_received(:save)
        expect(Onetime::Operations::Memberships::SetRole).not_to have_received(:new)
        expect(Onetime::AdminAuditEvent).not_to have_received(:record)
      end
    end

    describe 'refusals' do
      it 'returns :not_member when the target has no membership (D28)' do
        allow(Onetime::OrganizationMembership)
          .to receive(:find_by_org_customer).with('org-obj-1', 'cust-obj-new').and_return(nil)

        result = build.call

        expect(result.status).to eq(:not_member)
        expect(org).not_to have_received(:owner_id=)
        expect(Onetime::Operations::Memberships::SetRole).not_to have_received(:new)
        expect(Onetime::AdminAuditEvent).not_to have_received(:record)
      end

      it 'returns :not_member when the membership exists but is not active' do
        allow(target_membership).to receive(:active?).and_return(false)

        result = build.call

        expect(result.status).to eq(:not_member)
        expect(Onetime::Operations::Memberships::SetRole).not_to have_received(:new)
        expect(Onetime::AdminAuditEvent).not_to have_received(:record)
      end

      %w[owner bogus].each do |role|
        it "returns :invalid_role for --demote-to #{role}" do
          result = build(demote_to: role).call

          expect(result.status).to eq(:invalid_role)
          expect(org).not_to have_received(:owner_id=)
          expect(Onetime::Operations::Memberships::SetRole).not_to have_received(:new)
          expect(Onetime::AdminAuditEvent).not_to have_received(:record)
        end
      end

      it "excludes 'owner' from DEMOTABLE_ROLES, sourced from SetRole::VALID_ROLES" do
        expect(described_class::DEMOTABLE_ROLES).to contain_exactly('admin', 'member')
        expect(described_class::DEMOTABLE_ROLES)
          .to eq(Onetime::Operations::Memberships::SetRole::VALID_ROLES - ['owner'])
      end
    end

    describe 'idempotence' do
      it 'returns :no_change when the target is already the sole owner and owner_id agrees' do
        allow(target_membership).to receive(:owner?).and_return(true)
        allow(org).to receive(:owner_id).and_return('cust-obj-new')
        allow(Onetime::OrganizationMembership)
          .to receive(:active_for_org).with(org).and_return([target_membership])
        allow(Onetime::Customer).to receive(:load).with('cust-obj-new').and_return(new_owner)

        result = build.call

        expect(result.status).to eq(:no_change)
        expect(result.demoted).to be_empty
        expect(org).not_to have_received(:owner_id=)
        expect(org).not_to have_received(:save)
        expect(Onetime::Operations::Memberships::SetRole).not_to have_received(:new)
        expect(Onetime::AdminAuditEvent).not_to have_received(:record)
      end

      it 'repairs a partial state (already owner, stale owner_id) instead of reporting :no_change' do
        # This is exactly `org doctor` check 4: a role:'owner' membership whose
        # id != org.owner_id. It must NOT look like "nothing to do".
        allow(target_membership).to receive(:owner?).and_return(true)

        result = build.call

        expect(result.status).to eq(:success)
        expect(org).to have_received(:owner_id=).with('cust-obj-new')
        # Already an owner -> no promote call; only the demote.
        expect(calls).to eq([[:owner_id=, 'cust-obj-new'], ['ur_old_ext', 'admin']])
        expect(Onetime::AdminAuditEvent).to have_received(:record).once
      end
    end

    describe 'multi-owner orgs (D29)' do
      let(:second_old_owner) do
        instance_double(Onetime::Customer, extid: 'ur_old2_ext', objid: 'cust-obj-old2', anonymous?: false)
      end

      let(:second_old_membership) do
        instance_double(
          Onetime::OrganizationMembership,
          active?: true,
          owner?: true,
          customer_objid: 'cust-obj-old2',
          customer: second_old_owner,
        )
      end

      before do
        allow(Onetime::OrganizationMembership)
          .to receive(:active_for_org)
          .with(org)
          .and_return([old_owner_membership, second_old_membership, target_membership])
      end

      it 'demotes EVERY other active owner — the only outcome that passes doctor check 4' do
        result = build.call

        expect(result.demoted).to eq(['ur_old_ext', 'ur_old2_ext'])
        expect(calls).to eq(
          [
            ['ur_new_ext', 'owner'],
            [:owner_id=, 'cust-obj-new'],
            ['ur_old_ext', 'admin'],
            ['ur_old2_ext', 'admin'],
          ]
        )
        expect(Onetime::AdminAuditEvent).to have_received(:record).once
          .with(hash_including(detail: hash_including(demoted_count: 2)))
      end

      it 'lists every owner that would be demoted in the dry-run plan' do
        result = build(dry_run: true).call

        expect(result.demoted).to eq(['ur_old_ext', 'ur_old2_ext'])
      end
    end

    describe 'orphaned owner_id (D30 — proceed and repair)' do
      before do
        allow(Onetime::Customer).to receive(:load).with('cust-obj-old').and_return(nil)
      end

      it 'transfers anyway, flags orphaned_owner, and records a nil `from`' do
        result = build.call

        expect(result.status).to eq(:success)
        expect(result.orphaned_owner).to be(true)
        expect(result.from_owner_id).to be_nil
        expect(org).to have_received(:owner_id=).with('cust-obj-new')
        expect(Onetime::AdminAuditEvent).to have_received(:record).once
          .with(hash_including(detail: hash_including(from: nil)))
      end

      it 'treats a blank owner_id as orphaned without a customer lookup' do
        allow(org).to receive(:owner_id).and_return('')
        allow(Onetime::OrganizationMembership)
          .to receive(:active_for_org).with(org).and_return([target_membership])

        result = build.call

        expect(result.status).to eq(:success)
        expect(result.orphaned_owner).to be(true)
        expect(result.demoted).to be_empty
        expect(Onetime::Customer).not_to have_received(:load)
      end
    end

    describe 'stale owner membership with no backing customer (doctor check 3)' do
      it 'skips it rather than fabricating a Customer (ADR-023)' do
        allow(old_owner_membership).to receive(:customer).and_return(nil)

        result = build.call

        expect(result.status).to eq(:success)
        expect(result.demoted).to be_empty
        expect(calls).to eq([['ur_new_ext', 'owner'], [:owner_id=, 'cust-obj-new']])
      end
    end

    describe 'rollback' do
      it 'restores owner_id, un-promotes the new owner, re-raises, and audits NOTHING' do
        allow(Onetime::Operations::Memberships::SetRole).to receive(:new) do |args|
          calls << [args[:customer].extid, args[:new_role]]
          if args[:new_role] == 'admin' && args[:customer].extid == 'ur_old_ext'
            instance_double(Onetime::Operations::Memberships::SetRole, call: nil).tap do |dbl|
              allow(dbl).to receive(:call).and_raise(Onetime::Problem, 'boom')
            end
          else
            instance_double(
              Onetime::Operations::Memberships::SetRole,
              call: set_role_result(args[:customer], 'member', args[:new_role]),
            )
          end
        end

        expect { build.call }.to raise_error(Onetime::Problem, 'boom')

        expect(org).to have_received(:owner_id=).with('cust-obj-new').ordered
        expect(org).to have_received(:owner_id=).with('cust-obj-old').ordered
        # The new owner is put back at the role they held before the promote.
        expect(calls.last).to eq(['ur_new_ext', 'member'])
        expect(Onetime::AdminAuditEvent).not_to have_received(:record)
      end

      it 'raises when the promote itself fails, before any owner_id write' do
        allow(Onetime::Operations::Memberships::SetRole).to receive(:new) do |args|
          calls << [args[:customer].extid, args[:new_role]]
          instance_double(
            Onetime::Operations::Memberships::SetRole,
            call: Onetime::Operations::Memberships::SetRole::Result.new(
              status: :not_found, org_id: 'on_org_ext', customer_id: args[:customer].extid,
              from: nil, to: args[:new_role]
            ),
          )
        end

        expect { build.call }.to raise_error(Onetime::Problem, /Failed to set role 'owner'/)

        expect(org).not_to have_received(:owner_id=)
        expect(Onetime::AdminAuditEvent).not_to have_received(:record)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Layer 2 — real datastore. Proves the post-condition the mocked layer cannot:
  # both parties' entitlements are re-materialized and the org passes doctor.
  # ---------------------------------------------------------------------------
  describe 'real datastore', :datastore do
    let(:suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }

    before do
      # Layer 2 exercises the WRITE path, not the audit model. (The composed
      # SetRole calls would otherwise emit two real 'membership.set_role'
      # events into the capped admin audit set on every example.)
      allow(Onetime::AdminAuditEvent).to receive(:record)

      @customers = []
      @orgs      = []

      @owner_a = track_customer(Onetime::Customer.create!(email: "org_xfer_a_#{suffix}@onetimesecret.com"))
      @owner_b = track_customer(Onetime::Customer.create!(email: "org_xfer_b_#{suffix}@onetimesecret.com"))

      @org = Onetime::Organization.create!("Xfer #{suffix}", @owner_a)
      @orgs << @org
      Onetime::OrganizationMembership.ensure_membership(@org, @owner_b, role: 'member')
    end

    after do
      @orgs.each do |org|
        @customers.each do |cust|
          membership = Onetime::OrganizationMembership.find_by_org_customer(org.objid, cust.objid)
          membership.destroy! if membership.respond_to?(:exists?) && membership.exists?
        end
        org.destroy! if org.exists?
      rescue StandardError => ex
        warn "[org transfer spec] org cleanup failed: #{ex.class}: #{ex.message}"
      end
      @customers.each do |cust|
        cust.destroy! if cust.exists?
      rescue StandardError => ex
        warn "[org transfer spec] customer cleanup failed: #{ex.class}: #{ex.message}"
      end
    end

    def track_customer(cust)
      @customers << cust
      cust
    end

    def transfer(**overrides)
      described_class.new(
        **{ org: @org, new_owner: @owner_b, actor: actor, dry_run: false }.merge(overrides)
      ).call
    end

    def membership_for(customer)
      Onetime::OrganizationMembership.find_by_org_customer(@org.objid, customer.objid)
    end

    it 're-materializes BOTH sides: B gains manage_org, A loses it' do
      expect(membership_for(@owner_b).can?('manage_org')).to be(false)
      expect(membership_for(@owner_a).can?('manage_org')).to be(true)

      expect(transfer.status).to eq(:success)

      expect(membership_for(@owner_b).role).to eq('owner')
      expect(membership_for(@owner_b).can?('manage_org')).to be(true)
      expect(membership_for(@owner_a).role).to eq('admin')
      expect(membership_for(@owner_a).can?('manage_org')).to be(false)
    end

    it 'leaves the org passing ALL FIVE bin/ots org doctor checks, with exactly one owner' do
      transfer

      org = Onetime::Organization.load(@org.objid)
      expect(org_doctor_issues(org)).to be_empty
      expect(Onetime::OrganizationMembership.active_for_org(org).count(&:owner?)).to eq(1)
    end

    it 'pivots owner_id to the new owner OBJID and leaves created_by untouched (ADR-012)' do
      created_by_before = @org.created_by

      transfer

      org = Onetime::Organization.load(@org.objid)
      expect(org.owner_id).to eq(@owner_b.objid)
      expect(org.created_by).to eq(created_by_before)
      # D32: owner_id and created_by now disagree by design — the
      # standardize_owner_id chore warns about this org forever.
      expect(org.owner_id).not_to eq(org.created_by)
    end

    it 'keeps the outgoing owner an ACTIVE member (D27 — customers doctor check 1)' do
      transfer

      membership = membership_for(@owner_a)
      expect(membership).not_to be_nil
      expect(membership.active?).to be(true)
      expect(Onetime::Organization.load(@org.objid).member?(@owner_a)).to be(true)
    end

    it 'moves the sole-owner guard from A to B' do
      transfer

      org     = Onetime::Organization.load(@org.objid)
      support = Class.new { include Onetime::Operations::Memberships::Support }.new

      expect(support.sole_owner?(org, membership_for(@owner_b))).to be(true)
      expect(support.sole_owner?(org, membership_for(@owner_a))).to be(false)
    end

    it 'is idempotent — a second transfer to B is :no_change and mutates nothing' do
      transfer

      second = described_class.new(org: Onetime::Organization.load(@org.objid),
        new_owner: @owner_b, actor: actor, dry_run: false).call

      expect(second.status).to eq(:no_change)
      expect(membership_for(@owner_a).role).to eq('admin')
      expect(membership_for(@owner_b).role).to eq('owner')
      expect(Onetime::Organization.load(@org.objid).owner_id).to eq(@owner_b.objid)
    end

    it 'writes nothing on a dry run' do
      result = transfer(dry_run: true)

      expect(result.status).to eq(:planned)
      expect(result.demoted).to eq([@owner_a.extid])
      expect(Onetime::Organization.load(@org.objid).owner_id).to eq(@owner_a.objid)
      expect(membership_for(@owner_b).role).to eq('member')
    end

    it 'refuses a non-member target (:not_member) without touching the org' do
      outsider = track_customer(Onetime::Customer.create!(email: "org_xfer_out_#{suffix}@onetimesecret.com"))

      result = transfer(new_owner: outsider)

      expect(result.status).to eq(:not_member)
      expect(Onetime::Organization.load(@org.objid).owner_id).to eq(@owner_a.objid)
      expect(membership_for(@owner_a).role).to eq('owner')
    end
  end
end
