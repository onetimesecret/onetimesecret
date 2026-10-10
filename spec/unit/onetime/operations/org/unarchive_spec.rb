# spec/unit/onetime/operations/org/unarchive_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Operations::Org::Unarchive (#4717).
#
# The repair verb for organizations soft-archived by the tenant SSO
# self-heal (JoinDomainOrganization#adopt_domain_default_org archived the
# owner's OWN domain org when it was their is_default workspace). Modeled on
# Onetime::Operations::Org::TransferOwnership: one Result with `status`,
# `dry_run` defaulting to TRUE, exactly one `organization.unarchive` audit
# event on the applied path.
#
# TWO LAYERS, on purpose (same split as delete_spec.rb):
#
#   1. Mocked contract (no datastore) — the statuses, the "a preview or a
#      no-change writes NOTHING" assertions, the exactly-once audit event, and
#      the fact that the clear goes through Organization#unarchive! (the one
#      primitive that resets archived_at AND archived_comment together).
#
#   2. Real datastore (Valkey on 2163, see spec/config.test.yaml) — the
#      post-conditions that are unprovable with mocks: archived_at and
#      archived_comment are really empty on reload, a dry run leaves them, the
#      advisory pointer reads the owner's live default_org_id, and the audit
#      event lands in the operator trail exactly once.
#
# ## pointer_org_id is advisory, never a guard
#
# The self-heal only archives the workspace the owner's default pointer
# resolves to (explicit pointer, else the owned is_default workspace), so a
# pointer that names a DIFFERENT live org leaves this one untouched after the
# unarchive. The Result reports that org's extid so the operator can see the
# owner will not land here, and nothing refuses on it.
#
# Layer 2 registers every object it creates and destroys them in `after`. It
# NEVER flushes — the test datastore is shared.
#
# Run: tests/lanes/run unit --only spec/unit/onetime/operations/org/unarchive_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'onetime/operations/org/unarchive'

RSpec.describe Onetime::Operations::Org::Unarchive do
  let(:actor) { 'ur_col_public_extid' } # PUBLIC identity (extid/email)
  let(:archived_comment) { 'Superseded by domain org on_org_ext via SSO self-heal' }

  describe 'mocked contract' do
    let(:owner) do
      instance_double(
        Onetime::Customer,
        extid: 'ur_owner_ext',
        objid: 'cust-obj-owner',
        anonymous?: false,
        default_org_id: 'org-obj-1',
      )
    end

    let(:other_org) do
      instance_double(
        Onetime::Organization,
        extid: 'on_other_ext',
        objid: 'org-obj-other',
        display_name: 'Other Org',
        archived?: false,
      )
    end

    let(:org) do
      instance_double(
        Onetime::Organization,
        extid: 'on_org_ext',
        objid: 'org-obj-1',
        display_name: 'Test Org',
        owner_id: 'cust-obj-owner',
        archived?: true,
        archived_at: '1760000000.0',
        archived_comment: archived_comment,
        unarchive!: true,
        save: true,
      )
    end

    before do
      allow(Onetime::ColonelAuditEvent).to receive(:record)
      allow(Onetime::ColonelAuditEvent).to receive(:record_access)
      allow(OT).to receive(:info)
      allow(OT).to receive(:le)

      allow(Onetime::Customer).to receive(:load).with('cust-obj-owner').and_return(owner)
      allow(Onetime::Organization).to receive(:load).and_return(nil)
      allow(Onetime::Organization).to receive(:load).with('org-obj-1').and_return(org)
      allow(Onetime::Organization).to receive(:load).with('org-obj-other').and_return(other_org)
    end

    def build(**overrides)
      described_class.new(**{ org: org, actor: actor, dry_run: false }.merge(overrides))
    end

    describe 'happy path (applied)' do
      it 'returns a fully populated :success Result' do
        result = build.call

        expect(result.status).to eq(:success)
        expect(result.org_id).to eq('on_org_ext')          # PUBLIC extid, never the objid
        expect(result.display_name).to eq('Test Org')
        expect(result.owner_id).to eq('ur_owner_ext')      # PUBLIC extid, never the objid
        expect(result.pointer_org_id).to be_nil            # pointer names THIS org: not elsewhere
        expect(result.archived_comment).to eq(archived_comment)
        expect(result.dry_run).to be(false)
      end

      it 'exposes exactly the seven Result fields — there is no force override' do
        expect(described_class::Result.members).to eq(
          %i[status org_id display_name owner_id pointer_org_id archived_comment dry_run],
        )
        expect { described_class.new(org: org, actor: actor, force: true) }
          .to raise_error(ArgumentError, /force/)
      end

      it 'clears the archive through Organization#unarchive! exactly once' do
        build.call

        expect(org).to have_received(:unarchive!).once
      end

      it 'records EXACTLY ONE audit event, public ids only, carrying the cleared comment' do
        build.call

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          actor: actor,
          verb: 'organization.unarchive',
          target: 'on_org_ext',
          result: :success,
          detail: hash_including(archived_comment: archived_comment, pointer_org_id: nil),
        )
      end

      it 'uses the full-noun audit verb the rest of the trail uses' do
        expect(described_class::AUDIT_VERB).to eq('organization.unarchive')
      end

      it 'treats :planned, :success and :not_archived as non-failures, and has no refusal statuses' do
        expect(described_class::OK_STATUSES).to contain_exactly(:planned, :success, :not_archived)
        expect(described_class.const_defined?(:REFUSAL_STATUSES)).to be(false)
      end
    end

    describe 'dry run (THE DEFAULT)' do
      it 'defaults to dry_run: true — the repair never applies by accident' do
        result = described_class.new(org: org, actor: actor).call

        expect(result.status).to eq(:planned)
        expect(result.dry_run).to be(true)
      end

      it 'plans the unarchive and mutates NOTHING, with no operator-trail event' do
        result = build(dry_run: true).call

        expect(result.status).to eq(:planned)
        expect(result.archived_comment).to eq(archived_comment)
        expect(org).not_to have_received(:unarchive!)
        expect(org).not_to have_received(:save)
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      end
    end

    describe 'preview observation (#4337)' do
      it 'records exactly ONE record_access preview on a dry run, and no operator-trail event' do
        build(dry_run: true).call

        expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
          actor: actor,
          verb: 'organization.unarchive',
          target: 'on_org_ext',
          result: 'preview',
          detail: hash_including(dry_run: true, archived_comment: archived_comment, pointer_org_id: nil),
        )
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      end

      it 'records no preview on the applied path' do
        build.call

        expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access)
      end
    end

    describe ':not_archived (no change)' do
      before { allow(org).to receive(:archived?).and_return(false) }

      it 'returns :not_archived and writes nothing, on the applied path' do
        result = build.call

        expect(result.status).to eq(:not_archived)
        expect(org).not_to have_received(:unarchive!)
        expect(org).not_to have_received(:save)
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      end

      it 'returns :not_archived on a dry run too' do
        expect(build(dry_run: true).call.status).to eq(:not_archived)
        expect(org).not_to have_received(:unarchive!)
      end
    end

    # Advisory only (see the file header): a pointer at another live org is
    # reported, never refused, and the unarchive proceeds exactly as it would
    # with the pointer at this org.
    describe 'pointer_org_id (advisory)' do
      before { allow(owner).to receive(:default_org_id).and_return('org-obj-other') }

      it "reports the other LIVE org the owner's default_org_id names and still unarchives" do
        result = build.call

        expect(result.status).to eq(:success)
        expect(result.owner_id).to eq('ur_owner_ext')
        expect(result.pointer_org_id).to eq('on_other_ext') # PUBLIC extid of the org the pointer names
        expect(org).to have_received(:unarchive!).once
      end

      it 'carries the pointer in the single success event, with no forced marker' do
        recorded = []
        allow(Onetime::ColonelAuditEvent).to receive(:record) { |**kwargs| recorded << kwargs }

        build.call

        expect(recorded.size).to eq(1)
        expect(recorded.first).to include(verb: 'organization.unarchive', target: 'on_org_ext', result: :success)
        expect(recorded.first[:detail]).to include(pointer_org_id: 'on_other_ext', archived_comment: archived_comment)
        expect(recorded.first[:detail]).not_to have_key(:forced)
        expect(recorded.first[:detail]).not_to have_key(:force)
      end

      it 'plans normally on a dry run, reporting the pointer and writing nothing' do
        result = build(dry_run: true).call

        expect(result.status).to eq(:planned)
        expect(result.pointer_org_id).to eq('on_other_ext')
        expect(org).not_to have_received(:unarchive!)
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      end

      it 'is nil for a pointer at an ARCHIVED other org' do
        allow(other_org).to receive(:archived?).and_return(true)

        result = build.call

        expect(result.status).to eq(:success)
        expect(result.pointer_org_id).to be_nil
      end

      it 'is nil for a pointer at a MISSING org' do
        allow(owner).to receive(:default_org_id).and_return('org-obj-gone')

        result = build.call

        expect(result.status).to eq(:success)
        expect(result.pointer_org_id).to be_nil
      end

      it 'is nil for an empty pointer' do
        allow(owner).to receive(:default_org_id).and_return('')

        result = build.call

        expect(result.status).to eq(:success)
        expect(result.pointer_org_id).to be_nil
      end

      it 'is nil when owner_id resolves to no live customer (org doctor check 1)' do
        allow(Onetime::Customer).to receive(:load).with('cust-obj-owner').and_return(nil)

        result = build.call

        expect(result.status).to eq(:success)
        expect(result.owner_id).to be_nil
        expect(result.pointer_org_id).to be_nil
      end
    end

    # The Onetime::AuditedFailure mechanism, pinned the same way as
    # TransferOwnership's rollback spec: the success record sits AFTER
    # unarchive!, so a raise there would otherwise leave no trace. Message
    # expectations, not store reads: ColonelAuditEvent.record swallows its own
    # errors.
    describe 'a raising unarchive!' do
      before { allow(org).to receive(:unarchive!).and_raise(Onetime::Problem, 'boom') }

      it 're-raises and records ONE result: :failure event, never a success' do
        expect { build.call }.to raise_error(Onetime::Problem, 'boom')

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(
            actor: actor,
            verb: 'organization.unarchive',
            target: 'on_org_ext', # literal: a broken target lambda lands as 'unknown'
            result: :failure,
            detail: hash_including(error: 'Onetime::Problem', message: 'boom', dry_run: false),
          ),
        )
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record).with(hash_including(result: :success))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Layer 2 — real datastore. Proves what the mocked layer cannot: the fields
  # are really cleared on reload, the pointer guard reads a real default_org_id,
  # and the audit event is in the operator trail exactly once.
  # ---------------------------------------------------------------------------
  describe 'real datastore', :datastore do
    let(:suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }

    before do
      # Layer 2 exercises the WRITE path; the trail is asserted explicitly in
      # the one example that opts back in with and_call_original.
      allow(Onetime::ColonelAuditEvent).to receive(:record)
      allow(Onetime::ColonelAuditEvent).to receive(:record_access)

      @customers = []
      @orgs      = []

      @owner = track_customer(Onetime::Customer.create!(email: "org_unarch_#{suffix}@onetimesecret.com"))
      @org   = Onetime::Organization.create!("Unarch #{suffix}", @owner)
      @orgs << @org

      # The #4717 state: the owner's own default org, archived by the
      # self-heal with the self-referential comment, pointer still naming it.
      @org.is_default! true
      @owner.default_org_id = @org.objid
      @owner.save
      @org.archive!("Superseded by domain org #{@org.extid} via SSO self-heal")
      expect(Onetime::Organization.load(@org.objid).archived?).to be(true)
    end

    after do
      @orgs.each do |org|
        @customers.each do |cust|
          membership = Onetime::OrganizationMembership.find_by_org_customer(org.objid, cust.objid)
          membership.destroy! if membership.respond_to?(:exists?) && membership.exists?
        end
        org.destroy! if org.exists?
      rescue StandardError => ex
        warn "[org unarchive spec] org cleanup failed: #{ex.class}: #{ex.message}"
      end
      @customers.each do |cust|
        cust.destroy! if cust.exists?
      rescue StandardError => ex
        warn "[org unarchive spec] customer cleanup failed: #{ex.class}: #{ex.message}"
      end
    end

    def track_customer(cust)
      @customers << cust
      cust
    end

    def unarchive(**overrides)
      described_class.new(**{ org: @org, actor: actor, dry_run: false }.merge(overrides)).call
    end

    def reloaded_org
      Onetime::Organization.load(@org.objid)
    end

    it 'clears archived_at AND archived_comment on the persisted record' do
      expect(unarchive.status).to eq(:success)

      org = reloaded_org
      expect(org.archived?).to be(false)
      expect(org.archived_at.to_s).to be_empty
      expect(org.archived_comment.to_s).to be_empty
      # Nothing else moves: still the owner's default workspace, pointer intact.
      expect(org.is_default.to_s).to eq('true')
      expect(Onetime::Customer.load(@owner.objid).default_org_id).to eq(@org.objid)
    end

    it 'writes the organization.unarchive event to the operator trail exactly once' do
      allow(Onetime::ColonelAuditEvent).to receive(:record).and_call_original

      unarchive

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once
      events = Onetime::ColonelAuditEvent.recent(50).select do |event|
        event['verb'] == 'organization.unarchive' && event['target'] == @org.extid
      end
      expect(events.size).to eq(1)
      expect(events.first['result'].to_s).to eq('success')
      expect(events.first['actor']).to eq(actor)
    end

    it 'leaves the archive in place on a dry run' do
      result = unarchive(dry_run: true)

      expect(result.status).to eq(:planned)
      org = reloaded_org
      expect(org.archived?).to be(true)
      expect(org.archived_comment).to eq("Superseded by domain org #{@org.extid} via SSO self-heal")
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end

    it 'reports :not_archived for a live org and changes nothing' do
      @org.unarchive!

      expect(unarchive.status).to eq(:not_archived)
      expect(reloaded_org.archived?).to be(false)
    end

    # F4 (review on #4723): the CLI loads the org, then a billing webhook
    # moves planid / subscription fields on a different instance, then the
    # CLI's instance unarchives. Organization#unarchive! must write only its
    # two fields; a whole-hash save from the stale instance would put the old
    # billing values back and report success.
    it 'leaves billing fields changed by another instance after this one was loaded intact' do
      @org.planid                 = 'free_v1'
      @org.stripe_subscription_id = "sub_old_#{suffix}"
      @org.subscription_status    = 'canceled'
      @org.save

      stale = Onetime::Organization.load(@org.objid) # what the CLI holds

      webhook = Onetime::Organization.load(@org.objid)
      webhook.planid                 = 'team_plus_v1'
      webhook.stripe_subscription_id = "sub_new_#{suffix}"
      webhook.subscription_status    = 'active'
      webhook.save

      result = described_class.new(org: stale, actor: actor, dry_run: false).call
      expect(result.status).to eq(:success)

      org = reloaded_org
      expect(org.archived?).to be(false)
      expect(org.archived_comment.to_s).to be_empty
      expect(org.planid).to eq('team_plus_v1')
      expect(org.stripe_subscription_id).to eq("sub_new_#{suffix}")
      expect(org.subscription_status).to eq('active')
    end

    describe 'the advisory pointer over a real default_org_id' do
      before do
        @elsewhere = Onetime::Organization.create!("Elsewhere #{suffix}", @owner)
        @orgs << @elsewhere
        @owner.default_org_id = @elsewhere.objid
        @owner.save
      end

      it 'unarchives and reports the other live org the owner defaults to' do
        result = unarchive

        expect(result.status).to eq(:success)
        expect(result.pointer_org_id).to eq(@elsewhere.extid)
        expect(reloaded_org.archived?).to be(false)
      end

      it 'reports nil once the other org is archived too' do
        @elsewhere.archive!('test')

        result = unarchive

        expect(result.status).to eq(:success)
        expect(result.pointer_org_id).to be_nil
        expect(reloaded_org.archived?).to be(false)
      end
    end
  end
end
