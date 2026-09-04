# apps/api/colonel/spec/logic/colonel/revoke_all_customer_sessions_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# POST /api/colonel/users/:user_id/sessions/revoke-all — logs a customer out of
# EVERY device, so TIER 1 (#4326).
#
# This adapter is deliberately thin: Onetime::Operations::Sessions::RevokeAllForCustomer
# owns the purge and the single ColonelAuditEvent (CONTRACT 4). Since #4328 the
# account is resolved as a real 404 guard (an unknown identifier used to return
# zero counts, which reads as "done" for a typo), and a SELF-TARGET request is
# routed to RevokeAllForCustomerExceptCurrent rather than refused — killing your
# own other sessions is the first containment step for a leaked colonel cookie.
RSpec.describe ColonelAPI::Logic::Colonel::RevokeAllCustomerSessions do
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

  let(:target) do
    instance_double(Onetime::Customer,
      objid: 'cust_target', extid: 'ur_target', email: 'victim@example.com',
      exists?: true, anonymous?: false)
  end

  let(:op) do
    instance_double(
      Onetime::Operations::Sessions::RevokeAllForCustomer,
      call: Onetime::Operations::Sessions::RevokeAllForCustomer::Result.new(
        revoked: true, blobs_deleted: 2, untracked_deleted: 0,
        rodauth_rows_deleted: 0, scan_capped: false,
      ),
    )
  end

  # `confirm_token` is where the colonel session auth strategy puts the
  # percent-decoded X-OTS-Confirm header — never params.
  def strategy_result_for(user, confirm_token = 'victim@example.com', session = {})
    double('StrategyResult', session: session, user: user,
      auth_method: 'sessionauth', metadata: { confirm_token: confirm_token })
  end

  def logic_for(user = colonel, confirm_token = 'victim@example.com')
    described_class.new(strategy_result_for(user, confirm_token), { 'user_id' => 'ur_target' })
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(target)
    allow(Onetime::Customer).to receive(:load).and_return(target)
    allow(Onetime::Operations::Sessions::RevokeAllForCustomer).to receive(:new).and_return(op)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
  end

  describe 'confirmation (#4326)' do
    let(:expected_confirm_token) { 'victim@example.com' }

    def confirmed_logic_for(confirm_token)
      logic_for(colonel, confirm_token)
    end

    it_behaves_like 'a confirmed colonel action'

    it 'does not accept the extid the URL already carried' do
      expect { logic_for(colonel, 'ur_target').raise_concerns }
        .to raise_error(Onetime::ConfirmationRequired)
    end

    it 'revokes nothing when the confirmation is refused' do
      expect { logic_for(colonel, nil).raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
      expect(Onetime::Operations::Sessions::RevokeAllForCustomer).not_to have_received(:new)
    end

    # #4328 replaced P2's "fall back to the submitted identifier" with a real
    # 404: an unresolvable target now stops at guard-order step 2, BEFORE the
    # confirmation gate, so there is no expected token to name at all.
    it '404s before the gate when the account does not resolve' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)
      allow(Onetime::Customer).to receive(:load).and_return(nil)

      expect { logic_for(colonel, 'ur_target').raise_concerns }
        .to raise_error(Onetime::RecordNotFound)
      expect(Onetime::Operations::Sessions::RevokeAllForCustomer).not_to have_received(:new)
    end
  end

  # ---- Step-up (sudo) window (#4327) -----------------------------------------
  describe 'elevation' do
    let(:expected_confirm_token) { 'victim@example.com' }

    def elevated_logic_for(session, confirm_token = expected_confirm_token)
      described_class.new(
        strategy_result_for(colonel, confirm_token, session),
        { 'user_id' => 'ur_target' },
      )
    end

    it_behaves_like 'an elevated colonel action'
  end

  describe 'authorization' do
    it 'refuses a non-colonel and writes NO audit event' do
      expect { logic_for(customer, nil).raise_concerns }.to raise_error(Onetime::Forbidden)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end

  # ---- Self-target containment (#4328) ---------------------------------------
  #
  # Deliberately NOT a refusal (design M-6): "kill all my sessions" is the first
  # containment step for a leaked colonel cookie, so refusing it would remove
  # the operator's only in-console remedy for the compromise they are
  # containing. It routes to the except-current op instead.
  describe 'self-target' do
    let(:self_target) do
      instance_double(Onetime::Customer,
        objid: 'cust_colonel', extid: 'ur_colonel', email: 'colonel@example.com',
        exists?: true, anonymous?: false)
    end

    let(:except_op) do
      instance_double(
        Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent,
        call: Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent::Result.new(
          revoked: true, blobs_deleted: 3, untracked_deleted: 1, scan_capped: false,
        ),
      )
    end

    # A Rack SessionId: #public_id is the cookie value the ops key on.
    let(:rack_session_id) { double('SessionId', public_id: 'a' * 64) }

    def self_logic(session_id = rack_session_id)
      described_class.new(
        double('StrategyResult',
          session: double('Session', id: session_id),
          user: colonel, auth_method: 'sessionauth',
          metadata: { confirm_token: 'colonel@example.com' }),
        { 'user_id' => 'ur_colonel' },
      )
    end

    before do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(self_target)
      allow(Onetime::Customer).to receive(:load).and_return(self_target)
      allow(Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent)
        .to receive(:new).and_return(except_op)
    end

    it 'routes to the except-current op, excluding this request session' do
      logic = self_logic
      logic.raise_concerns
      logic.process

      expect(Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent)
        .to have_received(:new).with(hash_including(
          customer: self_target, except_session_id: 'a' * 64, actor: 'ur_colonel',
        ))
      expect(Onetime::Operations::Sessions::RevokeAllForCustomer).not_to have_received(:new)
    end

    # Same construction rule as the offboarding path below: raise_concerns
    # resolved (and the operator confirmed) THIS record, so the op gets the
    # record — never a `custid:` it would re-resolve through the extid index,
    # where a miss (#4205/#4217 drift) degrades to a silent zero-count revoke
    # that leaves the leaked colonel's other sessions live. Live-datastore
    # proof of that gap:
    # try/unit/operations/sessions/revoke_all_for_customer_except_current_try.rb
    it 'hands the except-current op the resolved record, never a re-resolvable extid' do
      logic = self_logic
      logic.raise_concerns
      logic.process

      expect(Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent)
        .to have_received(:new).once
      expect(Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent)
        .to have_received(:new).with(hash_including(customer: self_target))
      expect(Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent)
        .not_to have_received(:new).with(hash_including(:custid))
    end

    it 'tells the operator their current session was kept' do
      logic = self_logic
      logic.raise_concerns

      expect(logic.process[:details][:message]).to eq(described_class::SELF_TARGET_MESSAGE)
    end

    it 'reports zero rodauth rows (the except-current op is Redis-only)' do
      logic = self_logic
      logic.raise_concerns

      expect(logic.process[:record][:rodauth_rows_deleted]).to eq(0)
    end

    # Fail safe: with no identifiable current session the except-current op
    # would spare nothing and sign the operator out of the console.
    it '422s rather than self-revoking when the current sid cannot be resolved' do
      logic = self_logic(nil)

      expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /no identifiable session/)
      expect(Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent)
        .not_to have_received(:new)
    end

    # M-2 oracle guard: the fail-safe 422 must never be reachable without proof.
    it 'answers 403 (not the 422) when the confirmation is missing' do
      logic = described_class.new(
        double('StrategyResult', session: double('Session', id: nil), user: colonel,
          auth_method: 'sessionauth', metadata: { confirm_token: nil }),
        { 'user_id' => 'ur_colonel' },
      )

      expect { logic.raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
    end
  end

  describe 'the happy path still works' do
    it 'hands the op the resolved customer record and the acting colonel extid' do
      logic = logic_for
      logic.raise_concerns
      data = logic.process

      expect(Onetime::Operations::Sessions::RevokeAllForCustomer).to have_received(:new)
        .with(hash_including(customer: target, actor: 'ur_colonel'))
      expect(data[:record][:blobs_deleted]).to eq(2)
    end

    it 'records no audit event of its own (the op owns the trail)' do
      logic = logic_for
      logic.raise_concerns
      logic.process

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end
end
