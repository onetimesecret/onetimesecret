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
#      emits EXACTLY ONE AdminAuditEvent, and never calls org.remove_domain
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
require 'onetime/models/admin_audit_event'
require 'onetime/operations/domains/remove'

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

    before do
      allow(Onetime::AdminAuditEvent).to receive(:record)
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
        expect(Onetime::AdminAuditEvent).not_to have_received(:record)
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
        expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
          actor: actor,
          verb: 'domain.remove',
          target: 'cd_ext1',
          result: :success,
          detail: hash_including(reasserted: false),
        )
      end

      it 'does NOT call org.remove_domain (destroy! owns org participation)' do
        described_class.new(domain: domain, actor: actor, dry_run: false).call

        expect(org).not_to have_received(:remove_domain)
      end
    end

    # 3. orphaned domain (org_id blank) — org loads nil, still destroys + audits.
    describe 'orphaned domain (blank org_id)' do
      let(:domain) do
        instance_double(
          Onetime::CustomDomain,
          objid: 'cd-orphan',
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
        expect(Onetime::AdminAuditEvent).to have_received(:record).once
      end
    end

    # 4. delete_vhost transport error is swallowed; removal + audit still proceed.
    describe 'when delete_vhost raises a transport error' do
      before { allow(strategy).to receive(:delete_vhost).and_raise(Timeout::Error) }

      it 'swallows it, still destroys the record and audits exactly once' do
        result = described_class.new(domain: domain, actor: actor, dry_run: false).call

        expect(result.status).to eq(:removed)
        expect(domain).to have_received(:destroy!)
        expect(Onetime::AdminAuditEvent).to have_received(:record).once
      end
    end
  end

  # ------------------------------------------------------------------ #
  # Layer 2 — real datastore (the display_domain_index re-assertion crux)
  #
  # These require the test Valkey (spec/config.test.yaml -> :2121). No blanket
  # flush: each example registers its records/fqdns and the after(:each) hook
  # tears down only those, so nothing clobbers another example's fixtures.
  # ------------------------------------------------------------------ #
  describe 'real datastore', :datastore do
    let(:index) { Onetime::CustomDomain.display_domain_index }

    before do
      # Stub only the audit sink so we can count/inspect events without writing
      # to the shared capped audit set. Everything else (destroy!, the index,
      # the passthrough strategy, DeleteSenderDomain) runs for real.
      allow(Onetime::AdminAuditEvent).to receive(:record)
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
    # index already points at another record), so the raw "parse + save" bypass
    # the op's docstring describes no longer works directly. We reproduce the
    # SAME end state deterministically: drop the index entry so the guard passes,
    # save the shadow (which repoints the index at itself), then FORCE the index
    # back to the survivor. Result: two live hashes for one fqdn, index -> survivor.
    def create_shadow(fqdn, org_id, survivor)
      index.remove(fqdn)
      shadow = Onetime::CustomDomain.parse(fqdn, org_id)
      shadow.save
      @records << shadow
      index.put(fqdn, survivor.objid)
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
      expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
        hash_including(verb: 'domain.remove', result: :success, detail: hash_including(reasserted: true))
      )
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
      expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
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
      expect(Onetime::AdminAuditEvent).to have_received(:record).once
    end
  end
end
