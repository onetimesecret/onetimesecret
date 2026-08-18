# spec/unit/onetime/operations/org/delete_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Operations::Org::Delete (#4204).
#
# TWO LAYERS, on purpose:
#
#   1. Mocked contract (no datastore) — every guardrail status, the negative
#      "a refusal writes and audits NOTHING" assertions, the exactly-once audit
#      event, the notification isolation, and above all THE TEARDOWN ORDER:
#      snapshot -> instances.remove -> destroy! -> default_org_id -> notify.
#      Order is asserted directly (a shared call log) rather than inferred,
#      because every one of those steps is a different kind of wrong when it
#      runs late: a snapshot taken after destroy! notifies nobody, and an
#      instances entry left behind is the exact drift the console recipe causes.
#
#   2. Real datastore (Valkey on 2163, see spec/config.test.yaml) — the
#      post-conditions that are unprovable with mocks: the org is really gone
#      from `Organization.instances` (the acceptance criterion for this ticket),
#      the memberships are gone, the owner's `default_org_id` is cleared with no
#      `bin/ots customers doctor --repair` pass, and a DRY RUN leaves every one
#      of those untouched.
#
# Layer 2 registers every object it creates and destroys them in `after`. It
# NEVER flushes — the test datastore is shared.
#
# Run: bundle exec rspec spec/unit/onetime/operations/org/delete_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'onetime/operations/org/delete'

RSpec.describe Onetime::Operations::Org::Delete do
  let(:actor) { 'ur_col_public_extid' } # PUBLIC identity (extid/email)

  describe 'mocked contract' do
    # Ordered log of every state-changing call the op makes, so the
    # snapshot -> remove -> destroy -> repair -> notify sequence is asserted
    # directly rather than inferred.
    let(:calls) { [] }

    let(:owner) do
      instance_double(
        Onetime::Customer,
        extid: 'ur_owner',
        objid: 'cust-obj-owner',
        email: 'owner@example.com',
        locale: 'en',
        default_org_id: 'org-obj-1',
      )
    end

    let(:member) do
      instance_double(
        Onetime::Customer,
        extid: 'ur_member',
        objid: 'cust-obj-member',
        email: 'member@example.com',
        locale: '',
        default_org_id: '',
      )
    end

    let(:org) do
      instance_double(
        Onetime::Organization,
        objid: 'org-obj-1',
        extid: 'on_org_ext',
        display_name: 'Acme',
        planid: 'free_v1',
        is_default: 'false',
        owner_id: 'cust-obj-owner',
        pending_invitation_count: 2,
      )
    end

    let(:instances) { double('Instances') }

    before do
      allow(Onetime::ColonelAuditEvent).to receive(:record)
      allow(OT).to receive(:info)
      allow(OT).to receive(:le)
      allow(OT).to receive(:ld)
      allow(OT).to receive(:default_locale).and_return('en')

      allow(org).to receive(:list_members) do
        calls << :list_members
        [owner, member]
      end
      allow(org).to receive(:domain_count).and_return(0)
      allow(org).to receive(:list_domains).and_return([])
      allow(org).to receive(:active_subscription?).and_return(false)
      allow(org).to receive(:destroy!) { calls << :destroy! }

      allow(Onetime::Organization).to receive(:instances).and_return(instances)
      allow(instances).to receive(:remove) { |objid| calls << [:instances_remove, objid] }

      allow(Onetime::Customer).to receive(:load).with('cust-obj-owner').and_return(owner)
      # Two orgs: the last_org guard must NOT trip on the happy path.
      allow(owner).to receive(:organization_instances)
        .and_return(double('Participation', to_a: [org, double('OtherOrg', objid: 'org-obj-2')]))
      allow(owner).to receive(:default_org_id=) { |value| calls << [:default_org_id=, value] }
      allow(owner).to receive(:save) { calls << :save_owner }

      allow(Onetime::Jobs::Publisher).to receive(:enqueue_email) do |template, payload, **|
        calls << [:enqueue, template, payload[:email_address]]
        true
      end
    end

    def build(**overrides)
      described_class.new(**{ org: org, actor: actor }.merge(overrides))
    end

    describe 'dry run (THE DEFAULT — this is a destructive verb)' do
      it 'defaults to a preview and mutates nothing' do
        result = build.call

        expect(result.status).to eq(:planned)
        expect(result.dry_run).to be(true)
        expect(calls).to eq([:list_members])
        expect(org).not_to have_received(:destroy!)
        expect(instances).not_to have_received(:remove)
      end

      it 'audits nothing on the preview path' do
        build.call

        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      end

      it 'still reports what WOULD happen, so the plan and the receipt agree' do
        result = build.call

        expect(result.members.map { |m| m[:extid] }).to eq(%w[ur_owner ur_member])
        expect(result.members_notified).to eq(2)
        expect(result.default_org_cleared).to eq(['ur_owner'])
        expect(result.pending_invitations).to eq(2)
        expect(result.planid).to eq('free_v1')
        expect(result.owner_id).to eq('ur_owner')
        expect(result.owner_org_count).to eq(2)
      end
    end

    describe 'applied teardown' do
      it 'runs the steps in the ONE order that cannot lose data' do
        result = build(dry_run: false).call

        expect(result.status).to eq(:success)
        expect(calls).to eq(
          [
            :list_members,                          # snapshot BEFORE anything
            [:instances_remove, 'org-obj-1'],       # the step bin/console forgets
            :destroy!,
            [:default_org_id=, nil],                # the customer-row repair
            :save_owner,
            [:enqueue, :organization_deleted, 'owner@example.com'],
            [:enqueue, :organization_deleted, 'member@example.com'],
          ]
        )
      end

      it 'snapshots the recipients BEFORE destroy! empties the membership set' do
        build(dry_run: false).call

        expect(calls.index(:list_members)).to be < calls.index(:destroy!)
        expect(org).to have_received(:list_members).once
      end

      it 'records EXACTLY ONE audit event, public ids and counts only' do
        build(dry_run: false).call

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          actor: actor,
          verb: 'organization.delete',
          target: 'on_org_ext',
          result: :success,
          detail: {
            display_name: 'Acme',
            planid: 'free_v1',
            members: 2,
            members_notified: 2,
            pending_invitations: 2,
            default_org_cleared: 1,
            forced: [],
          },
        )
      end

      it 'clears default_org_id only for customers pointing at the dead org' do
        result = build(dry_run: false).call

        # The member's pointer is blank, so it is never written — `member` has
        # no `default_org_id=` stub at all, and a write would raise here.
        expect(result.default_org_cleared).to eq(['ur_owner'])
        expect(calls.count { |c| c.is_a?(Array) && c.first == :default_org_id= }).to eq(1)
      end

      it 'defaults the mail locale when a member carries a blank one' do
        build(dry_run: false).call

        expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email)
          .with(:organization_deleted, hash_including(locale: 'en'), any_args).twice
      end

      it 'names the acting identity in the notification by default' do
        build(dry_run: false).call

        expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email)
          .with(:organization_deleted, hash_including(deleted_by: actor), any_args).twice
      end

      it 'lets an adapter override deleted_by (the customer-facing wording)' do
        build(dry_run: false, deleted_by: 'someone@example.com').call

        expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email)
          .with(:organization_deleted, hash_including(deleted_by: 'someone@example.com'), any_args)
          .twice
      end
    end

    describe 'post-destroy failures never undo a committed delete' do
      it 'isolates a failing notification: the rest still send, the delete stands' do
        allow(Onetime::Jobs::Publisher).to receive(:enqueue_email) do |_t, payload, **|
          raise StandardError, 'queue down' if payload[:email_address] == 'owner@example.com'

          calls << [:enqueue, payload[:email_address]]
          true
        end

        result = build(dry_run: false).call

        expect(result.status).to eq(:success)
        expect(result.members_notified).to eq(1)
        expect(calls).to include([:enqueue, 'member@example.com'])
      end

      it 'isolates a failing default_org_id repair' do
        allow(owner).to receive(:save).and_raise(StandardError, 'redis blip')

        result = build(dry_run: false).call

        expect(result.status).to eq(:success)
        expect(result.default_org_cleared).to eq([])
        expect(OT).to have_received(:le).with(/Failed to clear default_org_id/)
      end
    end

    describe 'guardrails' do
      it 'refuses on domains and lists them for the remediation' do
        allow(org).to receive(:domain_count).and_return(1)
        allow(org).to receive(:list_domains)
          .and_return([double('Domain', display_domain: 'a.example.com')])

        result = build(dry_run: false).call

        expect(result.status).to eq(:has_domains)
        expect(result.domain_count).to eq(1)
        expect(result.domains).to eq(['a.example.com'])
      end

      it 'checks domains BEFORE anything mutates (destroy! raises on them)' do
        allow(org).to receive(:domain_count).and_return(1)
        allow(org).to receive(:list_domains)
          .and_return([double('Domain', display_domain: 'a.example.com')])

        build(dry_run: false).call

        expect(instances).not_to have_received(:remove)
        expect(org).not_to have_received(:destroy!)
      end

      # The count is what destroy! refuses on; list_domains compacts stale
      # entries away. Guarding on the NAMES would let this org through and blow
      # up inside destroy! — after instances.remove had already run.
      it 'refuses on a domains collection whose records no longer load' do
        allow(org).to receive(:domain_count).and_return(1)
        allow(org).to receive(:list_domains).and_return([])

        result = build(dry_run: false).call

        expect(result.status).to eq(:has_domains)
        expect(result.domain_count).to eq(1)
        expect(result.domains).to be_empty
        expect(org).not_to have_received(:destroy!)
      end

      it 'refuses a default workspace — the rule the UI enforced alone' do
        allow(org).to receive(:is_default).and_return('true')

        result = build(dry_run: false).call

        expect(result.status).to eq(:is_default)
        expect(result.is_default).to be(true)
        expect(org).not_to have_received(:destroy!)
      end

      it 'treats a non-"true" is_default as NOT default (conservative boolean)' do
        allow(org).to receive(:is_default).and_return('false')

        expect(build(dry_run: false).call.status).to eq(:success)
      end

      it 'refuses an actively-billing org and never calls Stripe' do
        allow(org).to receive(:active_subscription?).and_return(true)

        result = build(dry_run: false).call

        expect(result.status).to eq(:active_subscription)
        expect(org).not_to have_received(:destroy!)
      end

      it "refuses when the org is the owner's only one" do
        allow(owner).to receive(:organization_instances)
          .and_return(double('Participation', to_a: [org]))

        result = build(dry_run: false).call

        expect(result.status).to eq(:last_org)
        expect(result.owner_org_count).to eq(1)
        expect(org).not_to have_received(:destroy!)
      end

      # The guard asks what is LEFT, not how many rows exist: an owner who is
      # not a member of the org being deleted (org doctor check 2) still has
      # their other workspace afterwards.
      it 'counts what the owner keeps, not what they have' do
        allow(owner).to receive(:organization_instances)
          .and_return(double('Participation', to_a: [double('OtherOrg', objid: 'org-obj-2')]))

        expect(build(dry_run: false).call.status).to eq(:success)
      end

      it 'declines to speak when the owner cannot be resolved (org doctor check 1)' do
        allow(org).to receive(:owner_id).and_return('')
        allow(Onetime::OrganizationMembership).to receive(:active_for_org).with(org).and_return([])

        result = build(dry_run: false).call

        expect(result.status).to eq(:success)
        expect(result.owner_id).to be_nil
        expect(result.owner_org_count).to eq(0)
      end

      it 'audits NOTHING on a refusal (a customer can drive this path at will)' do
        allow(org).to receive(:is_default).and_return('true')

        build(dry_run: false).call

        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      end
    end

    describe 'force flags' do
      it 'unlocks only the guard it names — force_default leaves billing refused' do
        allow(org).to receive(:is_default).and_return('true')
        allow(org).to receive(:active_subscription?).and_return(true)

        result = build(dry_run: false, force_default: true).call

        expect(result.status).to eq(:active_subscription)
        expect(org).not_to have_received(:destroy!)
      end

      it 'applies once every tripped guard has its own override' do
        allow(org).to receive(:is_default).and_return('true')
        allow(org).to receive(:active_subscription?).and_return(true)

        result = build(dry_run: false, force_default: true, force_subscription: true).call

        expect(result.status).to eq(:success)
        expect(org).to have_received(:destroy!)
      end

      it 'records WHICH overrides were exercised, so the trail shows the decision' do
        allow(org).to receive(:is_default).and_return('true')

        build(dry_run: false, force_default: true).call

        expect(Onetime::ColonelAuditEvent).to have_received(:record)
          .with(hash_including(detail: hash_including(forced: ['is_default'])))
      end

      it 'never claims an override that was not needed' do
        build(dry_run: false, force_default: true, force_subscription: true).call

        expect(Onetime::ColonelAuditEvent).to have_received(:record)
          .with(hash_including(detail: hash_including(forced: [])))
      end

      it 'has no override for :last_org or :has_domains' do
        allow(owner).to receive(:organization_instances)
          .and_return(double('Participation', to_a: [org]))
        allow(org).to receive(:is_default).and_return('true')

        result = build(dry_run: false, force_default: true, force_subscription: true).call

        expect(result.status).to eq(:last_org)
      end
    end

    describe 'failure auditing (AuditedFailure)' do
      it 'records one result: failure and re-raises when the teardown blows up' do
        allow(org).to receive(:destroy!).and_raise(Onetime::Problem, 'boom')

        expect { build(dry_run: false).call }.to raise_error(Onetime::Problem, 'boom')

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(
            verb: 'organization.delete',
            target: 'on_org_ext',
            result: :failure,
          )
        )
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Layer 2 — real datastore. Proves the post-conditions the mocked layer cannot:
  # the instances-zset removal (this ticket's headline acceptance criterion) and
  # the default_org_id repair that keeps `customers doctor` clean with no
  # --repair pass.
  # ---------------------------------------------------------------------------
  describe 'real datastore', :datastore do
    let(:suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }

    before do
      # Layer 2 exercises the WRITE path, not the audit model or the mailer.
      allow(Onetime::ColonelAuditEvent).to receive(:record)
      allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)

      @customers = []
      @orgs      = []

      @owner = track_customer(Onetime::Customer.create!(email: "org_del_a_#{suffix}@onetimesecret.com"))

      @org = Onetime::Organization.create!("Del #{suffix}", @owner)
      # A SECOND org, so the :last_org guard does not trip: this spec is about
      # the teardown, and that guard has its own coverage above.
      @keeper = Onetime::Organization.create!("Keep #{suffix}", @owner)
      @orgs.concat([@org, @keeper])

      # The dirty pointer a hand-run destroy! leaves behind.
      @owner.default_org_id = @org.objid
      @owner.save
    end

    after do
      @orgs.each do |org|
        @customers.each do |cust|
          membership = Onetime::OrganizationMembership.find_by_org_customer(org.objid, cust.objid)
          membership.destroy! if membership.respond_to?(:exists?) && membership.exists?
        end
        org.destroy! if org.exists?
      rescue StandardError => ex
        warn "[org delete spec] org cleanup failed: #{ex.class}: #{ex.message}"
      end
      @customers.each do |cust|
        cust.destroy! if cust.exists?
      rescue StandardError => ex
        warn "[org delete spec] customer cleanup failed: #{ex.class}: #{ex.message}"
      end
    end

    def track_customer(cust)
      @customers << cust
      cust
    end

    def delete(**overrides)
      described_class.new(**{ org: @org, actor: actor, dry_run: false }.merge(overrides)).call
    end

    def in_instances?(objid)
      Onetime::Organization.instances.revrangeraw(0, -1).include?(objid)
    end

    it 'removes the org from Organization.instances (the console-recipe gap)' do
      objid = @org.objid
      expect(in_instances?(objid)).to be(true)

      expect(delete.status).to eq(:success)

      expect(in_instances?(objid)).to be(false)
      expect(Onetime::Organization.load(objid)).to be_nil
    end

    it 'tears down the membership with the org' do
      delete

      membership = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @owner.objid)
      expect(membership.nil? || !membership.exists?).to be(true)
    end

    it "clears the owner's default_org_id — no customers doctor --repair needed" do
      result = delete

      expect(result.default_org_cleared).to eq([@owner.extid])
      expect(Onetime::Customer.load(@owner.objid).default_org_id.to_s).to be_empty
    end

    it 'leaves EVERYTHING untouched on a dry run' do
      objid = @org.objid

      result = delete(dry_run: true)

      expect(result.status).to eq(:planned)
      expect(in_instances?(objid)).to be(true)
      expect(Onetime::Organization.load(objid)).not_to be_nil
      expect(Onetime::Customer.load(@owner.objid).default_org_id).to eq(objid)
    end

    it "does not touch the owner's other organizations" do
      delete

      expect(in_instances?(@keeper.objid)).to be(true)
      expect(Onetime::Organization.load(@keeper.objid)).not_to be_nil
    end
  end
end
