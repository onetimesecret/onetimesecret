# apps/api/colonel/spec/logic/colonel/delete_secret_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# DELETE /api/colonel/secrets/:secret_id was the only destructive colonel route
# with no audit trail — purge, domain remove, session delete and DLQ purge all
# record. These examples pin the trail this adapter now owns: the exact verb,
# a PUBLIC target, an objid-free payload, the failure event, and the fact that
# an authorization rejection writes nothing.
RSpec.describe ColonelAPI::Logic::Colonel::DeleteSecret do
  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel',
      role: 'colonel', verified?: true, anonymous?: false)
  end

  let(:customer) do
    instance_double(Onetime::Customer,
      objid: 'cust_plain', extid: 'ur_plain',
      role: 'customer', verified?: true, anonymous?: false)
  end

  let(:secret) do
    instance_double(Onetime::Secret,
      exists?: true,
      objid: 'sec_internal_objid_do_not_leak',
      shortid: 'sec12345',
      state: 'new',
      owner_id: 'cust_owner_internal',
      receipt_identifier: 'rec_internal_objid',
      # nil, as on real records: the stored field is not populated by spawn_pair,
      # so the confirmation token falls back to the loaded receipt's shortid.
      receipt_shortid: nil,
      destroy!: true)
  end

  let(:receipt) do
    instance_double(Onetime::Receipt,
      exists?: true,
      objid: 'rec_internal_objid',
      shortid: 'rec98765',
      destroy!: true)
  end

  # `confirm_token` is where the colonel session auth strategy puts the
  # percent-decoded X-OTS-Confirm header (#4326) — never params. The default is
  # the RECEIPT shortid: the accepted token is independent of :secret_id (#4326).
  def strategy_result_for(user, confirm_token = 'rec98765', session = {})
    double('StrategyResult', session: session, user: user,
      auth_method: 'sessionauth', metadata: { confirm_token: confirm_token })
  end

  def logic_for(user = colonel)
    described_class.new(strategy_result_for(user), { 'secret_id' => 'sec12345abcdef' })
  end

  # ---- Server-side confirmation (#4326) --------------------------------------

  # The receipt shortid, NOT the secret shortid: the route is keyed by
  # :secret_id and secret.shortid == secret_id[0,8], so a token equal to it
  # would be derivable from the URL and no second factor at all (design §1.1).
  let(:expected_confirm_token) { 'rec98765' }

  def confirmed_logic_for(confirm_token)
    described_class.new(
      strategy_result_for(colonel, confirm_token),
      { 'secret_id' => 'sec12345abcdef' },
    )
  end

  it_behaves_like 'a confirmed colonel action'

  # ---- Confirmation-token independence from the URL (#4326) -------------------
  #
  # The whole point of #4326 is that a scraped-URL replay needs a SECOND,
  # non-URL identifier. The route is keyed by :secret_id, so the accepted token
  # must have entropy the URL does not carry — it must NOT equal, nor be a
  # prefix of, the :secret_id path parameter. secret.shortid IS secret_id[0,8]
  # (a prefix), so it must be rejected; the receipt shortid (its own objid) is
  # what is accepted.
  describe 'confirmation-token independence from :secret_id (#4326)' do
    let(:secret_id_param) { 'sec12345abcdef' }

    it 'requires a token that is neither equal to nor a prefix of :secret_id' do
      expect(expected_confirm_token).not_to eq(secret_id_param)
      expect(secret_id_param).not_to start_with(expected_confirm_token)
      expect(secret_id_param).not_to include(expected_confirm_token)
    end

    it 'rejects the secret shortid (= :secret_id[0,8]), which the URL carries' do
      logic = confirmed_logic_for(secret.shortid)
      expect { logic.raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
    end

    it 'accepts the receipt shortid, which the URL does not carry' do
      logic = confirmed_logic_for(receipt.shortid)
      expect { logic.raise_concerns }.not_to raise_error
    end
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Onetime::Secret).to receive(:load).and_return(secret)
    allow(Onetime::Receipt).to receive(:load).and_return(receipt)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
  end

  # ---- Step-up (sudo) window (#4327) -----------------------------------------
  describe 'elevation' do
    def elevated_logic_for(session, confirm_token = expected_confirm_token)
      described_class.new(
        strategy_result_for(colonel, confirm_token, session),
        { 'secret_id' => 'sec12345abcdef' },
      )
    end

    it_behaves_like 'an elevated colonel action'

    # Guard order (§0.2 step 3): elevation precedes token COMPUTATION, not just
    # token comparison (#4326/#4327 review). A receiptless secret's
    # confirmation_token fails closed (GuardMisconfigured, 500), but that raise
    # must not pre-empt require_elevation! — an unelevated caller gets 403
    # ElevationRequired first, so the 500 is never a confirmation oracle.
    context 'with a receiptless secret (confirmation_token fails closed)' do
      before do
        stub_colonel_elevation(enabled: true, window: 600)
        allow(secret).to receive(:receipt_identifier).and_return(nil)
        allow(secret).to receive(:receipt_shortid).and_return(nil)
      end

      it 'answers ElevationRequired (403), NOT GuardMisconfigured (500), when unelevated' do
        expect { elevated_logic_for({}).raise_concerns }
          .to raise_error(Onetime::ElevationRequired)
      end

      it 'still fails closed with GuardMisconfigured once the caller IS elevated' do
        session = elevated_session(colonel.extid)
        expect { elevated_logic_for(session).raise_concerns }
          .to raise_error(Onetime::GuardMisconfigured)
      end
    end
  end

  describe 'success path' do
    it 'records exactly one secret.delete event with the acting colonel as actor' do
      logic = logic_for
      logic.raise_concerns
      logic.process

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(
          actor: 'ur_colonel',
          verb: 'secret.delete',
          target: 'sec12345',
          result: :success,
        ),
      )
    end

    it 'keeps internal objids out of the audit payload (target and detail)' do
      logic = logic_for
      logic.raise_concerns
      logic.process

      payload = nil
      expect(Onetime::ColonelAuditEvent).to have_received(:record) { |args| payload = args }

      serialized = [payload[:target], payload[:detail]].inspect
      expect(serialized).not_to include('sec_internal_objid_do_not_leak')
      expect(serialized).not_to include('rec_internal_objid')
      expect(serialized).not_to include('cust_owner_internal')
      expect(payload[:detail]).to eq(state: 'new', receipt_shortid: 'rec98765')
    end

    it 'still returns the incumbent response shape (unchanged public API)' do
      logic = logic_for
      logic.raise_concerns
      data = logic.process

      expect(data[:record][:deleted]).to be true
      expect(data[:record][:secret][:shortid]).to eq('sec12345')
      expect(data[:record][:metadata][:shortid]).to eq('rec98765')
    end
  end

  describe 'failure path (Onetime::AuditedFailure)' do
    it 'records result: :failure when the destroy raises, and re-raises' do
      allow(secret).to receive(:destroy!).and_raise(Familia::Problem, 'datastore exploded')

      logic = logic_for
      logic.raise_concerns

      expect { logic.process }.to raise_error(Familia::Problem, 'datastore exploded')

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(
          actor: 'ur_colonel',
          verb: 'secret.delete',
          target: 'sec12345',
          result: :failure,
          detail: hash_including(error: 'Familia::Problem'),
        ),
      )
    end
  end

  describe 'authorization rejection' do
    # The hard constraint: the audit set is capped by count with no TTL, so a
    # rejection that writes an event is a log-eviction primitive. The check
    # lives in raise_concerns, which Otto runs BEFORE the audited #process —
    # structurally outside the recorded region.
    it 'writes NO event when a non-colonel is refused' do
      logic = logic_for(customer)

      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end
end
