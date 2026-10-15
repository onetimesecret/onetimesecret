# spec/unit/onetime/operations/domains/remove_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Operations::Domains::Remove (#3731 P3) — the single
# toolbox implementation of the domain remove verb behind the colonel endpoint
# and 'bin/ots domains remove'.
#
# Two layers:
#
#   1. Mocked contract — dry-run previews nothing, apply tears down in the
#      RemoveDomain#process order (delete_vhost -> DeleteSenderDomain -> destroy!),
#      emits EXACTLY ONE ColonelAuditEvent, and never calls org.remove_domain
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
# Run: RACK_ENV=test bundle exec rspec spec/unit/onetime/operations/domains/remove_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'onetime/operations/domains/remove'
require 'onetime/operations/provision_sender_domain'

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

    # The FQDN index: .get returns the victim's own objid, i.e. NO drift — the
    # index points at the record being removed (reasserts_survivor false).
    let(:index) { double('display_domain_index', get: 'cd-obj-1', put: nil) }

    let(:strategy) { double('Strategy', delete_vhost: { message: 'noop' }) }

    let(:sender_op) { double('DeleteSenderDomain', call: nil) }

    let(:lock) do
      double('Familia::Lock', acquire: 'lock-token', release: true,
        dbkey: 'sender-identity-lock', dbclient: double('Redis', eval: 1))
    end

    before do
      allow(Onetime::ColonelAuditEvent).to receive(:record)
      allow(Onetime::CustomDomain::MailerConfig).to receive(:sender_identity_lock).and_return(lock)
      allow(Onetime::Organization).to receive(:load).with('org-1').and_return(org)
      allow(Onetime::CustomDomain).to receive(:display_domain_index).and_return(index)
      allow(Onetime::DomainValidation::Strategy).to receive(:for_config).and_return(strategy)
      allow(Onetime::Operations::DeleteSenderDomain).to receive(:new).and_return(sender_op)
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
        expect(result.reasserts_survivor).to be false

        expect(domain).not_to have_received(:destroy!)
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
        expect(lock).not_to have_received(:acquire)
      end
    end

    # 2. apply teardown order + exactly-one audit + no org.remove_domain.
    describe 'apply (dry_run: false)' do
      it 'tears down the vhost, sender domain, then destroys the record' do
        described_class.new(domain: domain, actor: actor, dry_run: false).call

        expect(strategy).to have_received(:delete_vhost).with(domain)
        expect(Onetime::Operations::DeleteSenderDomain)
          .to have_received(:new).with(mailer_config: mailer_config)
        expect(sender_op).to have_received(:call)
        expect(domain).to have_received(:destroy!)
      end

      it 'records EXACTLY ONE audit event (verb domain.remove, success, reasserted false)' do
        result = described_class.new(domain: domain, actor: actor, dry_run: false).call

        expect(result.status).to eq(:removed)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          actor: actor,
          verb: 'domain.remove',
          target: 'cd_ext1',
          result: :success,
          detail: hash_including(reasserted: false),
          # #4333: destroy! has committed by now, so the write is fail-closed.
          fail_closed: true,
        )
      end

      it 'does NOT call org.remove_domain (destroy! owns org participation)' do
        described_class.new(domain: domain, actor: actor, dry_run: false).call

        expect(org).not_to have_received(:remove_domain)
      end

      it "holds the domain's sender identity lock from the teardown through destroy!" do
        calls = []
        allow(lock).to receive(:acquire) do
          calls << :acquire
          'lock-token'
        end
        allow(strategy).to receive(:delete_vhost) do
          calls << :delete_vhost
          { message: 'noop' }
        end
        allow(sender_op).to receive(:call) { calls << :delete_sender_domain }
        allow(domain).to receive(:destroy!) { calls << :destroy! }
        allow(lock).to receive(:release) { calls << :release }

        described_class.new(domain: domain, actor: actor, dry_run: false).call

        expect(Onetime::CustomDomain::MailerConfig).to have_received(:sender_identity_lock).with('cd-obj-1')
        expect(lock).to have_received(:acquire).with(ttl: 60)
        expect(lock).to have_received(:release).with('lock-token')
        expect(calls).to eq([:acquire, :delete_vhost, :delete_sender_domain, :destroy!, :release])
      end
    end

    # Provisioning, a sender config delete, or another removal holds the lock:
    # refuse before any teardown, and record the refused attempt.
    describe 'while another holder has the sender identity lock' do
      before { allow(lock).to receive(:acquire).and_return(false) }

      it 'raises SenderIdentityBusy and tears nothing down' do
        expect do
          described_class.new(domain: domain, actor: actor, dry_run: false).call
        end.to raise_error(described_class::SenderIdentityBusy, /secrets\.example\.com/)

        expect(strategy).not_to have_received(:delete_vhost)
        expect(Onetime::Operations::DeleteSenderDomain).not_to have_received(:new)
        expect(domain).not_to have_received(:destroy!)
        expect(lock).not_to have_received(:release)
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

    describe 'when lease renewal fails during teardown' do
      [:vhost, :sender].each do |phase|
        [0, IOError.new('renewal unavailable')].each do |failure|
          it "stops after #{phase} on #{failure.inspect} and audits the failed removal" do
            lose_lease = proc do
              if failure.is_a?(Exception)
                allow(lock.dbclient).to receive(:eval).and_raise(failure)
              else
                allow(lock.dbclient).to receive(:eval).and_return(failure)
              end
              { message: 'done' }
            end
            if phase == :vhost
              allow(strategy).to receive(:delete_vhost, &lose_lease)
              expect(sender_op).not_to receive(:call)
            else
              allow(sender_op).to receive(:call, &lose_lease)
            end

            expect do
              described_class.new(domain: domain, actor: actor, dry_run: false).call
            end.to raise_error(Onetime::Operations::SenderIdentityLease::Lost)

            expect(domain).not_to have_received(:destroy!)
            expect(lock).to have_received(:release).with('lock-token')
            expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
              hash_including(verb: 'domain.remove', result: :failure,
                detail: hash_including(error: Onetime::Operations::SenderIdentityLease::Lost.name))
            )
          end
        end
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
      let(:index) { double('display_domain_index', get: 'cd-orphan', put: nil) }

      it 'destroys, audits once, and reports org_name nil' do
        result = described_class.new(domain: domain, actor: actor, dry_run: false).call

        expect(Onetime::Organization).not_to have_received(:load)
        expect(result.status).to eq(:removed)
        expect(result.org_name).to be_nil
        expect(domain).to have_received(:destroy!)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once
      end
    end

    # 4. delete_vhost transport error is swallowed; removal + audit still proceed.
    describe 'when delete_vhost raises a transport error' do
      before { allow(strategy).to receive(:delete_vhost).and_raise(Timeout::Error) }

      it 'swallows it, still destroys the record and audits exactly once' do
        result = described_class.new(domain: domain, actor: actor, dry_run: false).call

        expect(result.status).to eq(:removed)
        expect(domain).to have_received(:destroy!)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once
      end
    end

    it 'does not relabel a committed removal as failed when its committed-outcome audit write fails' do
      allow(domain).to receive(:destroy!) do
        allow(lock.dbclient).to receive(:eval).and_return(0)
      end
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

    # 5. Onetime::AuditedFailure — a removal that raises past the swallowed
    # vhost error records the ATTEMPT (the success record above is unreachable)
    # and re-raises unchanged.
    describe 'when the destroy itself raises' do
      before { allow(domain).to receive(:destroy!).and_raise(Familia::Problem, 'datastore gone') }

      it 'records one domain.remove failure at the extid, then re-raises' do
        expect do
          described_class.new(domain: domain, actor: actor, dry_run: false).call
        end.to raise_error(Familia::Problem, 'datastore gone')

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

      it 'releases the sender identity lock' do
        expect do
          described_class.new(domain: domain, actor: actor, dry_run: false).call
        end.to raise_error(Familia::Problem)

        expect(lock).to have_received(:release).with('lock-token')
      end
    end

    # dry_run defaults to TRUE and the success event is applied-path-only (a
    # preview mutates and audits nothing), so without this flag in the detail a
    # blown-up PREVIEW would be indistinguishable from a blown-up removal.
    describe 'when a dry-run preview raises' do
      before { allow(index).to receive(:get).and_raise(Familia::Problem, 'index read failed') }

      it 'marks the failure dry_run: true' do
        expect do
          described_class.new(domain: domain, actor: actor).call
        end.to raise_error(Familia::Problem, 'index read failed')

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

    # 5. Re-assertion: removing a shadow must re-point the index at the survivor.
    it 're-asserts the survivor pointer after destroying a shared-hostname shadow' do
      fqdn      = unique_fqdn('reassert')
      survivor  = create_domain(fqdn, "orgA-#{SecureRandom.hex(3)}")
      shadow    = create_shadow(fqdn, "orgB-#{SecureRandom.hex(3)}", survivor)

      # Setup confirmation: a dry-run on the shadow sees the drift.
      preview = described_class.new(domain: shadow, actor: 'cli', dry_run: true).call
      expect(preview.reasserts_survivor).to be true

      result = described_class.new(domain: shadow, actor: 'cli', dry_run: false).call

      expect(result.status).to eq(:removed)
      expect(result.reasserts_survivor).to be true
      # (a) the shadow hash is gone
      expect(shadow.exists?).to be false
      # (b) the index STILL points at the survivor (re-asserted, not wiped)
      expect(index.get(fqdn)).to eq(survivor.objid)
      # (c) resolution follows the index to the survivor
      expect(Onetime::CustomDomain.load_by_display_domain(fqdn).objid).to eq(survivor.objid)
      # (d) exactly one audit, flagged as a re-assertion
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(verb: 'domain.remove', result: :success, detail: hash_including(reasserted: true))
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
        allow(Onetime::CustomDomain).to receive(:load).and_call_original if shadow_removal

        expect do
          described_class.new(domain: domain, actor: 'cli', dry_run: false).call
        end.to raise_error(described_class::RemovalCommitted) { |ex|
          expect(ex.result.status).to eq(:removed)
          expect(ex.result.extid).to eq(extid)
          expect(ex.message).to include('removal committed', 'lock lost')
        }

        expect(domain.exists?).to be false
        expect(index.get(fqdn)).to eq(shadow_removal ? survivor.objid : nil)
        expect(Onetime::CustomDomain).to have_received(:load).with(survivor.objid) if shadow_removal
        expect(sender_op).to have_received(:call).once
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(hash_including(
          verb: 'domain.remove', target: extid, result: :success,
          detail: hash_including(removal_committed: true, lease_lost: true, reasserted: shadow_removal),
          fail_closed: true
        ))
      end
    end

    # 6. Normal removal clears the index — the entry is NOT resurrected.
    it 'clears the index on a normal removal (no re-assertion)' do
      fqdn   = unique_fqdn('clear')
      domain = create_domain(fqdn, "org-#{SecureRandom.hex(3)}")

      expect(index.get(fqdn)).to eq(domain.objid) # sanity: index points at it

      result = described_class.new(domain: domain, actor: 'cli', dry_run: false).call

      expect(result.status).to eq(:removed)
      expect(result.reasserts_survivor).to be false
      expect(index.get(fqdn)).to be_nil
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(detail: hash_including(reasserted: false))
      )
    end

    # 7. Pre-drifted index (owner already nil): removal is a clean no-op re index.
    it 'handles a pre-drifted nil index owner without error or re-assertion' do
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
      expect(result.reasserts_survivor).to be false
      expect(index.get(fqdn)).to be_nil
      expect(domain.exists?).to be false
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once
    end

    # Provisioning and the removal's provider teardown share this lock. A
    # provision between the teardown and destroy! would register the identity
    # again, and destroy! would then delete the only record of it.
    context 'with the sender identity lock' do
      let(:model) { Onetime::CustomDomain::MailerConfig }
      let(:domain) { create_domain(unique_fqdn('lock'), "org-#{SecureRandom.hex(3)}") }
      let(:lock) { model.sender_identity_lock(domain.identifier) }

      before do
        model.create!(
          domain_id: domain.identifier,
          provider: 'ses',
          from_address: 'remove-lock@example.com',
        )
      end

      def stub_teardown
        allow_any_instance_of(Onetime::Operations::DeleteSenderDomain).to receive(:call) do
          yield
          Onetime::Operations::DeleteSenderDomain::Result.new(success: true, message: 'stubbed', error: nil)
        end
      end

      def provision(config, strategy)
        Onetime::Operations::ProvisionSenderDomain.new(mailer_config: config, strategy: strategy).call
      end

      it 'refuses and keeps the domain and its sender config while another holder has the lock' do
        token = lock.acquire(ttl: 60)

        expect do
          described_class.new(domain: domain, actor: 'cli', dry_run: false).call
        end.to raise_error(described_class::SenderIdentityBusy)

        expect(domain.exists?).to be true
        expect(model.exists_for_domain?(domain.identifier)).to be true
      ensure
        lock.release(token)
      end

      it 'holds the lock from the provider teardown through destroy!' do
        seen = {}
        stub_teardown { seen[:teardown] = [lock.locked?, model.exists_for_domain?(domain.identifier)] }
        allow(domain).to receive(:destroy!).and_wrap_original do |original|
          seen[:destroy] = lock.locked?
          original.call
        end

        result = described_class.new(domain: domain, actor: 'cli', dry_run: false).call

        expect(result.status).to eq(:removed)
        expect(seen).to eq(teardown: [true, true], destroy: true)
        expect(lock.locked?).to be false
        expect(model.exists_for_domain?(domain.identifier)).to be false
      end

      [:vhost, :sender, :destroy].each do |phase|
        it "renews throughout slow #{phase} work beyond the initial lease" do
          stub_const('Onetime::Operations::SenderIdentityLease::TTL', 1)
          stub_const('Onetime::Operations::SenderIdentityLease::RENEW_INTERVAL', 0.05)
          stale = model.find_by_domain_id(domain.identifier)
          sender_strategy = spy('sender strategy')
          hold = proc do
            token = lock.value
            sleep 1.2
            expect(lock.held_by?(token)).to be true
            expect(lock.acquire(ttl: 1)).to be false
            expect(provision(stale, sender_strategy).error).to include('already in progress')
          end
          stub_teardown { hold.call if phase == :sender }
          if phase == :vhost
            vhost_strategy = double('vhost strategy')
            allow(vhost_strategy).to receive(:delete_vhost) { hold.call; { message: 'done' } }
            allow(Onetime::DomainValidation::Strategy).to receive(:for_config).and_return(vhost_strategy)
          elsif phase == :destroy
            allow(domain).to receive(:destroy!).and_wrap_original { |original| hold.call; original.call }
          end

          result = described_class.new(domain: domain, actor: 'cli', dry_run: false).call

          expect(result.status).to eq(:removed)
          expect(domain.exists?).to be false
          expect(lock.locked?).to be false
          expect(sender_strategy).not_to have_received(:provision_dns_records)
        end
      end

      it 'stops before destroy if the watchdog fails during a provider call, even after Redis recovers' do
        stub_const('Onetime::Operations::SenderIdentityLease::RENEW_INTERVAL', 0.01)
        client = lock.dbclient
        allow(lock).to receive(:dbclient).and_return(client)
        allow(model).to receive(:sender_identity_lock).with(domain.identifier).and_return(lock)
        allow(client).to receive(:eval).and_call_original
        attempted = Queue.new
        stub_teardown do
          allow(client).to receive(:eval)
            .with(Onetime::Operations::SenderIdentityLease::RENEW_SCRIPT, [lock.dbkey], anything) do
              attempted << true
              raise IOError, 'renewal unavailable'
            end
          Timeout.timeout(3) { attempted.pop }
          allow(client).to receive(:eval)
            .with(Onetime::Operations::SenderIdentityLease::RENEW_SCRIPT, [lock.dbkey], anything).and_return(1)
        end

        expect do
          described_class.new(domain: domain, actor: 'cli', dry_run: false).call
        end.to raise_error(Onetime::Operations::SenderIdentityLease::Lost, /renewal failed/)

        expect(domain.exists?).to be true
        expect(model.exists_for_domain?(domain.identifier)).to be true
        expect(lock.locked?).to be false
        expect(Onetime::ColonelAuditEvent).to have_received(:record).with(hash_including(result: :failure))
      end

      it 'does not provision during the removal, nor afterwards from a config loaded before it' do
        stale       = model.find_by_domain_id(domain.identifier)
        strategy    = spy('sender strategy')
        provisioned = nil
        stub_teardown { provisioned = provision(stale, strategy) }

        described_class.new(domain: domain, actor: 'cli', dry_run: false).call
        after_removal = provision(stale, strategy)

        expect(provisioned.error).to include('already in progress')
        expect(after_removal.error).to include('was deleted')
        expect(strategy).not_to have_received(:provision_dns_records)
      end
    end
  end
end
