# spec/unit/onetime/logic/colonel/sensitive_read_audit_spec.rb
#
# frozen_string_literal: true

# The CURATED SENSITIVE READS (#4335) — the colonel reads that now record an
# observation.
#
# CONTRACT 4 used to say "reads never audit"; it now says "reads never write
# the OPERATOR trail; curated sensitive reads write their own budgeted stream."
# These pin both halves per call site: `record_access` is called with the right
# verb/target/detail, and `record` (the operator trail) is never touched.
#
# The curation principle is that an observation is recorded when it EXPOSES
# CUSTOMER MATERIAL or is a BULK EXTRACTION — so each example below also says
# what the endpoint discloses.
#
# Message expectations, not store reads: record_access swallows its own errors
# and returns nil, so a store read could pass or fail for reasons unrelated to
# the mechanism (the failure_audit_spec.rb convention). The end-to-end store
# behaviour for the audit-log readers lives in
# spec/integration/all/colonel_observability_spec.rb and spec/cli/audit_command_spec.rb.
#
# Run: pnpm run test:rspec spec/unit/onetime/logic/colonel/sensitive_read_audit_spec.rb

require 'spec_helper'
require 'colonel/application'

RSpec.describe 'colonel sensitive-read auditing' do
  let(:colonel) do
    double(
      'Customer',
      extid: 'ur_colonel_public', role: 'colonel', objid: 'cust-obj-1',
      anonymous?: false, verified?: true,
    )
  end

  let(:strategy_result) do
    double(
      'StrategyResult',
      session: {}, user: colonel, metadata: { ip: '127.0.0.1' }, auth_method: 'sessionauth',
    )
  end

  before do
    allow(Onetime::ColonelAuditEvent).to receive(:record_access)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
  end

  # Every one of these mutates nothing, so the mutation trail must stay
  # untouched no matter what else they record. This is the half of CONTRACT 4
  # that protects `events` from read-volume eviction, and it did not change.
  RSpec.shared_examples 'never writes the operator trail' do
    it 'writes NOTHING to the operator trail' do
      run_read

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end

  # -- Secret receipt: discloses the OWNER'S FULL EMAIL ------------------------
  describe ColonelAPI::Logic::Colonel::GetSecretReceipt do
    let(:owner) { double('Customer', extid: 'ur_owner_public', objid: 'own-1', email: 'owner@example.com', role: 'customer', verified?: true) }
    let(:receipt) { double('Receipt', exists?: true, objid: 'rec-1', shortid: 'rc_short', state: 'received', secret_ttl: 60, recipients: [], has_passphrase?: false, share_domain: nil, created: 1, secret_expired?: false) }
    let(:secret) do
      double(
        'Secret',
        exists?: true, objid: 'sec-1', shortid: 'sh_abc', state: 'received',
        lifespan: 60, created: 1, updated: 2, expiration: 3, age: 4,
        owner_id: 'own-1', receipt_identifier: 'rec-1', ciphertext: 'xx',
      )
    end

    def run_read
      allow(Onetime::Secret).to receive(:load).with('sh_abc').and_return(secret)
      allow(Onetime::Receipt).to receive(:load).with('rec-1').and_return(receipt)
      allow(Onetime::Customer).to receive(:load).with('own-1').and_return(owner)

      logic = described_class.new(strategy_result, { 'secret_id' => 'sh_abc' })
      logic.process_params
      logic.raise_concerns
      logic.process
    end

    include_examples 'never writes the operator trail'

    it 'records ONE observation naming the secret by SHORTID' do
      run_read

      expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
        actor: 'ur_colonel_public',
        verb: 'secret.receipt_view',
        target: 'sh_abc',
        result: :success,
        detail: { state: 'received', owner_extid: 'ur_owner_public', receipt_shortid: 'rc_short' },
      )
    end

    # The response body carries the owner's address (that is what makes this a
    # curated read); the trail is longer-lived and must not copy it.
    it 'never puts the owner email or an internal objid in the trail' do
      run_read

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access).with(
        hash_including(detail: hash_including(:email)),
      )
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access).with(
        hash_including(target: 'sec-1'),
      )
    end
  end

  # -- Account diagnostics: auth-log tail + sessions for one person ------------
  describe ColonelAPI::Logic::Colonel::GetAccountDiagnostics do
    let(:user) { double('Customer', extid: 'ur_subject_public', objid: 'sub-1', email: 'subject@example.com') }
    let(:diagnosis) do
      double('Result', found?: true, findings: %w[locked_out no_mfa], sections: { 'auth_log' => %w[a b] })
    end

    def run_read(identifier: 'ur_subject_public', resolved: true)
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(resolved ? user : nil)
      allow(Onetime::Customer).to receive(:load).and_return(nil)
      allow(Auth::Operations::Customers::Diagnose).to receive(:new).and_return(
        double('Diagnose', call: diagnosis),
      )

      logic = described_class.new(strategy_result, { 'user_id' => identifier })
      logic.process_params
      logic.raise_concerns
      logic.process
    end

    include_examples 'never writes the operator trail'

    it 'records ONE observation with the SHAPE of the diagnosis, never its sections' do
      run_read

      expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
        actor: 'ur_colonel_public',
        verb: 'customer.diagnostics_view',
        target: 'ur_subject_public',
        result: :success,
        detail: hash_including(found: true, findings: 2),
      )
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access).with(
        hash_including(detail: hash_including(:sections)),
      )
    end

    # "No customer record" is itself a diagnosis here, not a 404 — so the read
    # still happened and still gets recorded, against what was typed. But this
    # identifier is email-tolerant by design, so what was typed is usually an
    # ADDRESS: it is masked with the same helper every other address-handling
    # emitter uses, because the event ships on the ColonelAudit sink.
    it 'obscures an unresolved identifier that is an email address' do
      run_read(identifier: 'ghost@example.com', resolved: false)

      expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
        hash_including(
          target: OT::Utils.obscure_email('ghost@example.com'),
          detail: hash_including(resolved: false),
        ),
      )
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access).with(
        hash_including(target: 'ghost@example.com'),
      )
    end

    # The mask is a text-level one, so a handle that carries no address is not
    # mangled — an operator still sees the extid they typed.
    it 'passes an unresolved non-address identifier through verbatim' do
      run_read(identifier: 'ur_typo_not_found', resolved: false)

      expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
        hash_including(target: 'ur_typo_not_found', detail: hash_including(resolved: false)),
      )
    end

    it 'marks a resolved read as resolved, so a masked target is unambiguous' do
      run_read

      expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
        hash_including(target: 'ur_subject_public', detail: hash_including(resolved: true)),
      )
    end
  end

  # -- Session inspection: decrypts one live session ---------------------------
  describe ColonelAPI::Logic::Colonel::GetSessionDetail do
    let(:raw_sid) { 'a' * 64 }
    let(:inspection) do
      double(
        'Result',
        found: true, session_id: raw_sid, key: "session:#{raw_sid}", ttl: 900,
        data: { 'authenticated' => true, 'email' => 'subject@example.com',
                'external_id' => 'ur_subject_public', 'ip_address' => '203.0.113.9' },
      )
    end

    def run_read
      allow(Onetime::Operations::Sessions::Inspect).to receive(:new).and_return(
        double('Inspect', call: inspection),
      )

      logic = described_class.new(strategy_result, { 'session_id' => raw_sid })
      logic.process_params
      logic.raise_concerns
      logic.process
    end

    include_examples 'never writes the operator trail'

    # THE load-bearing assertion. A live session's id is the cookie itself
    # (F-01), and audit events are emitted to the ColonelAudit log sink and
    # leave the process immediately — so recording the raw sid would put a
    # replayable credential into the log stream.
    it 'targets the non-reversible session HANDLE, never the bearer sid' do
      run_read

      expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
        hash_including(
          verb: 'session.inspect',
          target: Onetime::SessionMetadata.handle_for(raw_sid),
        ),
      )
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access).with(
        hash_including(target: raw_sid),
      )
    end

    it 'records who the session belonged to, not the decrypted payload' do
      run_read

      expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
        hash_including(detail: { authenticated: true, subject_extid: 'ur_subject_public' }),
      )
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access).with(
        hash_including(detail: hash_including(:email)),
      )
    end
  end
end
