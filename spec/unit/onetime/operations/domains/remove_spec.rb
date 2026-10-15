# spec/unit/onetime/operations/domains/remove_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Operations::Domains::Remove (#3731 P3) — the single
# toolbox implementation of the domain remove verb behind the colonel endpoint
# and 'bin/ots domains remove'.
#
# Two layers:
#
#   1. Mocked contract — dry-run skips teardown, apply delegates to the shared
#      Teardown operation, emits EXACTLY ONE ColonelAuditEvent,
#      and never calls org.remove_domain
#      (destroy! owns org participation). No datastore.
#
#   2. Real datastore — the display_domain_index re-assertion crux. Familia's
#      destroy! ends in a bare `super` whose transaction UNCONDITIONALLY HDELs
#      display_domain_index[fqdn] with no owner check, so removing a drift-shadow
#      would wipe the surviving canonical owner's pointer. These examples build
#      REAL CustomDomain records (super's HDEL only fires against real Redis) and
#      prove the survivor pointer is re-asserted, that a normal removal clears the
#      index (not resurrected), and that a pre-drifted nil owner is a no-op.
#
# Run: tests/lanes/run --only spec/unit/onetime/operations/domains/remove_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'onetime/operations/domains/remove'
require 'onetime/operations/domains/teardown'

RSpec.describe Onetime::Operations::Domains::Remove do
  # ------------------------------------------------------------------ #
  # Layer 1 — mocked contract (no datastore)
  # ------------------------------------------------------------------ #
  describe 'mocked contract' do
    let(:actor) { 'ur_col_public_extid' } # PUBLIC identity (extid), never an objid

    let(:mailer_config) { double('MailerConfig') }

    let(:domain) do
      instance_double(
        Onetime::CustomDomain,
        objid: 'cd-obj-1',
        identifier: 'cd-obj-1',
        domainid: 'cd-obj-1',
        extid: 'cd_ext1',
        display_domain: 'secrets.example.com',
        org_id: 'org-1',
        mailer_config: mailer_config,
        destroy!: true,
      )
    end

    let(:org) { double('Organization', display_name: 'Acme Inc', remove_domain: nil) }

    let(:teardown_result) do
      Onetime::Operations::Domains::Teardown::Result.new(removal_committed: true, lease_error: nil)
    end
    let(:teardown) { instance_double(Onetime::Operations::Domains::Teardown, call: teardown_result) }
    let(:lease_error) { Onetime::Operations::SenderIdentityLease::Lost.new('Sender identity lock lost') }

    before do
      allow(Onetime::ColonelAuditEvent).to receive(:record)
      allow(Onetime::Operations::Domains::Teardown).to receive(:new).with(domain: domain).and_return(teardown)
      allow(Onetime::Organization).to receive(:load).with('org-1').and_return(org)
    end

    # 1. dry-run (default) previews everything, mutates and audits nothing.
    describe 'dry run (default)' do
      it 'returns status :planned with the full echoed Result and mutates nothing' do
        result = described_class.new(domain: domain, actor: actor).call

        expect(result.status).to eq(:planned)
        expect(result.dry_run).to be true
        expect(result.domain_id).to eq('cd-obj-1')
        expect(result.extid).to eq('cd_ext1')
        expect(result.display_domain).to eq('secrets.example.com')
        expect(result.org_id).to eq('org-1')
        expect(result.org_name).to eq('Acme Inc')

        expect(domain).not_to have_received(:destroy!)
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
        expect(Onetime::Operations::Domains::Teardown).not_to have_received(:new)
        expect(teardown).not_to have_received(:call)
      end
    end

    # 2. apply delegation + exactly-one audit + no org.remove_domain.
    describe 'apply (dry_run: false)' do
      it 'delegates teardown exactly once to the shared operation' do
        described_class.new(domain: domain, actor: actor, dry_run: false).call

        expect(Onetime::Operations::Domains::Teardown).to have_received(:new).with(domain: domain).once
        expect(teardown).to have_received(:call).once
        expect(domain).not_to have_received(:destroy!)
      end

      it 'records EXACTLY ONE audit event (verb domain.remove, success)' do
        result = described_class.new(domain: domain, actor: actor, dry_run: false).call

        expect(result.status).to eq(:removed)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          actor: actor,
          verb: 'domain.remove',
          target: 'cd_ext1',
          result: :success,
          detail: hash_including(org_id: 'org-1'),
          # #4333: destroy! has committed by now, so the write is fail-closed.
          fail_closed: true,
        )
      end

      it 'does NOT call org.remove_domain (destroy! owns org participation)' do
        described_class.new(domain: domain, actor: actor, dry_run: false).call

        expect(org).not_to have_received(:remove_domain)
      end
    end

    # Provisioning, a sender config delete, or another removal holds the lock:
    # refuse before any teardown, and record the refused attempt.
    describe 'while another holder has the sender identity lock' do
      let(:busy_message) { 'Another change to the sender configuration of secrets.example.com is in progress. Try again.' }
      before do
        allow(teardown).to receive(:call)
          .and_raise(Onetime::Operations::Domains::Teardown::Busy, busy_message)
      end

      it 'raises SenderIdentityBusy and tears nothing down' do
        expect do
          described_class.new(domain: domain, actor: actor, dry_run: false).call
        end.to raise_error(described_class::SenderIdentityBusy, busy_message) { |ex|
          expect(ex.class.name).to eq("Onetime::Operations::Domains::Remove::SenderIdentityBusy")
        }

        expect(domain).not_to have_received(:destroy!)
      end

      it 'records one domain.remove failure' do
        expect do
          described_class.new(domain: domain, actor: actor, dry_run: false).call
        end.to raise_error(described_class::SenderIdentityBusy)

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(
            verb: 'domain.remove',
            target: 'cd_ext1',
            result: :failure,
            detail: hash_including(error: described_class::SenderIdentityBusy.name, dry_run: false),
          ),
        )
      end
    end

    describe 'when shared teardown loses the lease before commitment' do
      it 'propagates the same loss and audits the failed removal once' do
        allow(teardown).to receive(:call).and_raise(lease_error)

        expect do
          described_class.new(domain: domain, actor: actor, dry_run: false).call
        end.to raise_error { |ex| expect(ex).to equal(lease_error) }

        expect(domain).not_to have_received(:destroy!)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(verb: 'domain.remove', result: :failure,
            detail: hash_including(error: Onetime::Operations::SenderIdentityLease::Lost.name))
        )
      end
    end

    describe 'when shared teardown returns committed lease loss' do
      let(:teardown_result) do
        Onetime::Operations::Domains::Teardown::Result.new(removal_committed: true, lease_error: lease_error)
      end

      it 'carries the removed result and original cause, auditing success rather than failure' do
        expect do
          described_class.new(domain: domain, actor: actor, dry_run: false).call
        end.to raise_error(described_class::RemovalCommitted) { |ex|
          expect(ex.result).to be_a(described_class::Result)
          expect(ex.result.status).to eq(:removed)
          expect(ex.result.extid).to eq('cd_ext1')
          expect(ex.message).to include('removal committed', lease_error.message)
          expect(ex.cause).to equal(lease_error)
        }
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(hash_including(
          result: :success, fail_closed: true,
          detail: hash_including(removal_committed: true, lease_lost: true)
        ))
      end
    end

    # 3. orphaned domain (blank org_id) — org loads nil, still destroys + audits.
    describe 'orphaned domain (blank org_id)' do
      let(:domain) do
        instance_double(
          Onetime::CustomDomain,
          objid: 'cd-orphan',
          identifier: 'cd-orphan',
          domainid: 'cd-orphan',
          extid: 'cd_orphan',
          display_domain: 'orphan.example.com',
          org_id: '',
          mailer_config: mailer_config,
          destroy!: true,
        )
      end
      it 'delegates teardown, audits once, and reports org_name nil' do
        result = described_class.new(domain: domain, actor: actor, dry_run: false).call

        expect(Onetime::Organization).not_to have_received(:load)
        expect(result.status).to eq(:removed)
        expect(result.org_name).to be_nil
        expect(teardown).to have_received(:call).once
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once
      end
    end

    it 'does not relabel a committed removal as failed when its committed-outcome audit write fails' do
      allow(teardown).to receive(:call).and_return(
        Onetime::Operations::Domains::Teardown::Result.new(removal_committed: true, lease_error: lease_error)
      )
      allow(Onetime::ColonelAuditEvent).to receive(:record)
        .with(hash_including(verb: 'domain.remove'))
        .and_raise(Onetime::AuditWriteFailure.new(verb: 'domain.remove', target: 'cd_ext1'))

      expect do
        described_class.new(domain: domain, actor: actor, dry_run: false).call
      end.to raise_error(Onetime::AuditWriteFailure)

      expect(Onetime::ColonelAuditEvent).to have_received(:record).with(hash_including(
        verb: 'domain.remove', result: :success,
        detail: hash_including(removal_committed: true, lease_lost: true), fail_closed: true
      ))
      expect(Onetime::ColonelAuditEvent).to have_received(:record).with(hash_including(
        verb: 'audit.write_failure', target: 'cd_ext1', result: :failure
      ))
    end

    # Unexpected shared-operation failures are audited and re-raised unchanged.
    describe 'when shared teardown raises an unexpected error' do
      let(:error) { Familia::Problem.new('datastore gone') }
      before { allow(teardown).to receive(:call).and_raise(error) }

      it 'records one domain.remove failure at the extid, then re-raises' do
        expect do
          described_class.new(domain: domain, actor: actor, dry_run: false).call
        end.to raise_error { |ex| expect(ex).to equal(error) }

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(
            actor: actor,
            verb: 'domain.remove',
            target: 'cd_ext1',
            result: :failure,
            detail: hash_including(error: 'Familia::Problem', dry_run: false),
          ),
        )
      end

    end

    # dry_run defaults to TRUE and the success event is applied-path-only (a
    # preview mutates and audits nothing), so without this flag in the detail a
    # blown-up PREVIEW would be indistinguishable from a blown-up removal.
    describe 'when a dry-run preview raises' do
      before { allow(Onetime::Organization).to receive(:load).and_raise(Familia::Problem, 'organization read failed') }

      it 'marks the failure dry_run: true' do
        expect do
          described_class.new(domain: domain, actor: actor).call
        end.to raise_error(Familia::Problem, 'organization read failed')

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(
            verb: 'domain.remove',
            result: :failure,
            detail: hash_including(dry_run: true),
          ),
        )
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Layer 2 — real datastore (the display_domain_index re-assertion crux)
  #
  # These require the test Valkey (spec/config.test.yaml -> :2163). No blanket
  # flush: each example registers its records/fqdns and the after(:each) hook
  # tears down only those, so nothing clobbers another example's fixtures.
  # ------------------------------------------------------------------ #
  describe 'real datastore', :datastore do
    let(:index) { Onetime::CustomDomain.display_domain_index }

    before do
      # Stub only the audit sink so we can count/inspect events without writing
      # to the shared capped audit set. Everything else (destroy!, the index,
      # the passthrough strategy, DeleteSenderDomain) runs for real.
      allow(Onetime::ColonelAuditEvent).to receive(:record)
      @records = []
      @fqdns   = []
    end

    after do
      @records.each do |rec|
        rec.destroy! if rec.exists?
      rescue StandardError => ex
        warn "[remove_spec cleanup] #{ex.class}: #{ex.message}"
      end
      @fqdns.uniq.each { |fqdn| index.remove(fqdn) }
    end

    # Create a real, fully-persisted canonical domain and register it for cleanup.
    def create_domain(fqdn, org_id)
      rec = Onetime::CustomDomain.create!(fqdn, org_id)
      @records << rec
      @fqdns << fqdn
      rec
    end

    # Fabricate a drift SHADOW hash for an fqdn already owned by `survivor`.
    #
    # Familia 2.11's save now guards unique indexes (RecordExistsError if the
    # index already points at another record), and CustomDomain's save claims
    # the canonical name (CustomDomain::IdentityGuard), so the raw "parse +
    # save" bypass the op's docstring describes no longer works directly. We
    # reproduce the SAME end state deterministically: drop both index entries
    # so the guards pass, save the shadow (which points both at itself), then
    # FORCE both back to the survivor. Result: two live hashes for one fqdn,
    # both indexes -> survivor.
    def create_shadow(fqdn, org_id, survivor)
      canonical_index = Onetime::CustomDomain.canonical_display_domain_index
      canonical       = Onetime::CustomDomain.canonical_display_domain(fqdn)
      index.remove(fqdn)
      canonical_index.remove_field(canonical)
      shadow = Onetime::CustomDomain.parse(fqdn, org_id)
      shadow.save
      @records << shadow
      index.put(fqdn, survivor.objid)
      canonical_index.put(canonical, survivor.objid)
      shadow
    end

    def unique_fqdn(prefix)
      fqdn = "#{prefix}-#{SecureRandom.hex(4)}.example.com"
      @fqdns << fqdn
      fqdn
    end

    # 5. Removing a shadow leaves the survivor's index entries in place:
    #    destroy! releases its entries ownership-checked, so nothing is repaired.
    it 'leaves the survivor pointer in place after destroying a shared-hostname shadow' do
      fqdn       = unique_fqdn('shadow')
      survivor   = create_domain(fqdn, "orgA-#{SecureRandom.hex(3)}")
      shadow_org = "orgB-#{SecureRandom.hex(3)}"
      shadow     = create_shadow(fqdn, shadow_org, survivor)
      canonical  = Onetime::CustomDomain.canonical_display_domain(fqdn)

      result = described_class.new(domain: shadow, actor: 'cli', dry_run: false).call

      expect(result.status).to eq(:removed)
      # (a) the shadow hash is gone
      expect(shadow.exists?).to be false
      # (b) both index entries still name the survivor
      expect(index.get(fqdn)).to eq(survivor.objid)
      expect(Onetime::CustomDomain.canonical_display_domain_index.get(canonical)).to eq(survivor.objid)
      # (c) resolution follows the index to the survivor
      expect(Onetime::CustomDomain.load_by_display_domain(fqdn).objid).to eq(survivor.objid)
      # (d) exactly one audit
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(verb: 'domain.remove', result: :success, detail: hash_including(org_id: shadow_org))
      )
    end

    [false, true].each do |shadow_removal|
      it "finalizes and audits a committed #{shadow_removal ? 'shadow' : 'normal'} removal before reporting post-destroy lease loss" do
        fqdn = unique_fqdn('committed')
        survivor = create_domain(fqdn, "org-#{SecureRandom.hex(3)}") if shadow_removal
        domain = shadow_removal ? create_shadow(fqdn, 'shadow-org', survivor) : create_domain(fqdn, 'victim-org')
        extid = domain.extid
        lock = Onetime::CustomDomain::MailerConfig.sender_identity_lock(domain.identifier)
        sender_op = double('DeleteSenderDomain', call: nil)
        allow(Onetime::Operations::DeleteSenderDomain).to receive(:new).and_return(sender_op)
        allow(domain).to receive(:destroy!).and_wrap_original do |original|
          value = original.call
          lock.force_unlock!
          value
        end

        expect do
          described_class.new(domain: domain, actor: 'cli', dry_run: false).call
        end.to raise_error(described_class::RemovalCommitted) { |ex|
          expect(ex.result.status).to eq(:removed)
          expect(ex.result.extid).to eq(extid)
          expect(ex.message).to include('removal committed', 'lock lost')
        }

        expect(domain.exists?).to be false
        expect(index.get(fqdn)).to eq(shadow_removal ? survivor.objid : nil)
        expect(sender_op).to have_received(:call).once
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(hash_including(
          verb: 'domain.remove', target: extid, result: :success,
          detail: hash_including(removal_committed: true, lease_lost: true),
          fail_closed: true
        ))
      end
    end

    # 6. Normal removal clears both index entries.
    it 'clears the index entries on a normal removal' do
      fqdn      = unique_fqdn('clear')
      org_id    = "org-#{SecureRandom.hex(3)}"
      domain    = create_domain(fqdn, org_id)
      canonical = Onetime::CustomDomain.canonical_display_domain(fqdn)

      expect(index.get(fqdn)).to eq(domain.objid) # sanity: index points at it

      result = described_class.new(domain: domain, actor: 'cli', dry_run: false).call

      expect(result.status).to eq(:removed)
      expect(index.get(fqdn)).to be_nil
      expect(Onetime::CustomDomain.canonical_display_domain_index.get(canonical)).to be_nil
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(detail: hash_including(org_id: org_id))
      )
    end

    # 7. Pre-drifted index (owner already nil): removal is a clean no-op re index.
    it 'handles a pre-drifted nil index owner without error' do
      fqdn   = unique_fqdn('predrift')
      domain = create_domain(fqdn, "org-#{SecureRandom.hex(3)}")

      # Drift: HDEL the index entry directly, leaving the record hash intact.
      index.remove(fqdn)
      expect(index.get(fqdn)).to be_nil
      expect(domain.exists?).to be true

      result = nil
      expect {
        result = described_class.new(domain: domain, actor: 'cli', dry_run: false).call
      }.not_to raise_error

      expect(result.status).to eq(:removed)
      expect(index.get(fqdn)).to be_nil
      expect(domain.exists?).to be false
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once
    end

  end
end
