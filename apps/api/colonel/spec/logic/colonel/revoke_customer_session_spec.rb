# apps/api/colonel/spec/logic/colonel/revoke_customer_session_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# DELETE /api/colonel/users/:user_id/sessions/:session_handle — the per-customer
# twin of the global DeleteSession, and TIER 1 like it.
#
# This adapter owns HTTP concerns only: it resolves the non-bearer handle back to
# a sid by recomputing handles over the OWNING customer's own active-session set
# (so an untrusted handle can only ever name one of that customer's sessions, and
# the raw sid never leaves the server), then hands the sid to
# Onetime::Operations::Sessions::RevokeForCustomer, which owns the mutation and
# the ColonelAuditEvent (CONTRACT 4).
#
# The examples here pin the two guards this file gained in the hardening epic:
# the confirmation + elevation gate (#4326/#4327) and the self-revoke interlock
# (#4328), which runs AFTER them so its 422 is not a free "is this handle mine?"
# oracle for a caller holding nothing but the cookie.
RSpec.describe ColonelAPI::Logic::Colonel::RevokeCustomerSession do
  let(:target_sid) { 'b' * 64 }
  let(:own_sid)    { 'c' * 64 }
  let(:handle)     { Onetime::SessionMetadata.handle_for(target_sid) }
  let(:own_handle) { Onetime::SessionMetadata.handle_for(own_sid) }

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

  let(:owner) do
    instance_double(Onetime::Customer,
      objid: 'cust_owner', extid: 'ur_owner', email: 'owner@example.com',
      exists?: true, anonymous?: false, active_sessions: active_sessions)
  end

  # Customer#active_sessions is a sorted set; the adapter reads it with
  # revrange(0, -1) and matches by recomputed handle.
  let(:active_sessions) { double('SortedSet', revrange: [target_sid, own_sid]) }

  let(:op) do
    instance_double(
      Onetime::Operations::Sessions::RevokeForCustomer,
      call: Onetime::Operations::Sessions::RevokeForCustomer::Result.new(
        session_id: target_sid, revoked: true, blob_deleted: true,
      ),
    )
  end

  # `confirm_token` is where the colonel session auth strategy puts the
  # percent-decoded X-OTS-Confirm header — never params. `session_id` is the
  # acting colonel's OWN request session (a Rack SessionId; #public_id is the
  # cookie value), which is what the self-revoke interlock digests.
  def strategy_result_for(user, confirm_token = 'owner@example.com', session_id: nil, session: nil)
    sess = session || double('Session', id: session_id && double('SessionId', public_id: session_id))
    double('StrategyResult', session: sess, user: user,
      auth_method: 'sessionauth', metadata: { confirm_token: confirm_token })
  end

  def logic_for(user = colonel, confirm_token = 'owner@example.com',
                target_handle = handle, session_id: nil)
    described_class.new(
      strategy_result_for(user, confirm_token, session_id: session_id),
      { 'user_id' => 'ur_owner', 'session_handle' => target_handle },
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(owner)
    allow(Onetime::Customer).to receive(:load).and_return(owner)
    allow(Onetime::Operations::Sessions::RevokeForCustomer).to receive(:new).and_return(op)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
  end

  describe 'confirmation (#4326)' do
    let(:expected_confirm_token) { 'owner@example.com' }

    def confirmed_logic_for(confirm_token)
      logic_for(colonel, confirm_token)
    end

    it_behaves_like 'a confirmed colonel action'

    it 'does not accept the opaque handle the URL already carried' do
      expect { logic_for(colonel, handle).raise_concerns }
        .to raise_error(Onetime::ConfirmationRequired)
    end

    it 'revokes nothing when the confirmation is refused' do
      expect { logic_for(colonel, nil).raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
      expect(Onetime::Operations::Sessions::RevokeForCustomer).not_to have_received(:new)
    end
  end

  describe 'elevation (#4327)' do
    let(:expected_confirm_token) { 'owner@example.com' }

    def elevated_logic_for(session, confirm_token = expected_confirm_token)
      described_class.new(
        strategy_result_for(colonel, confirm_token, session: session),
        { 'user_id' => 'ur_owner', 'session_handle' => handle },
      )
    end

    it_behaves_like 'an elevated colonel action'
  end

  describe 'handle resolution' do
    it 'hands the OP the resolved sid, never the submitted handle' do
      logic = logic_for
      logic.raise_concerns
      logic.process

      expect(Onetime::Operations::Sessions::RevokeForCustomer).to have_received(:new)
        .with(custid: 'ur_owner', session_id: target_sid, actor: 'ur_colonel')
    end

    it '404s before the gate when the handle names none of the customer sessions' do
      expect { logic_for(colonel, nil, 'f' * 32).raise_concerns }
        .to raise_error(Onetime::RecordNotFound)
    end

    it 'echoes the handle and never the sid' do
      logic = logic_for
      logic.raise_concerns
      response = logic.process

      expect(response[:record][:session_handle]).to eq(handle)
      expect(response.to_s).not_to include(target_sid)
    end
  end

  # ---- Self-target interlock (#4328) -----------------------------------------
  describe 'self-target' do
    it 'refuses revoking your own active session, naming session_handle' do
      logic = logic_for(colonel, 'owner@example.com', own_handle, session_id: own_sid)

      expect { logic.raise_concerns }
        .to raise_error(Onetime::FormError, /Cannot revoke your own active session/)
      expect(Onetime::Operations::Sessions::RevokeForCustomer).not_to have_received(:new)
    end

    it 'proceeds for any other handle in the same listing' do
      logic = logic_for(colonel, 'owner@example.com', handle, session_id: own_sid)

      expect { logic.raise_concerns }.not_to raise_error
    end

    it 'does not raise when the request session has no resolvable id' do
      expect { logic_for(colonel, 'owner@example.com', own_handle).raise_concerns }
        .not_to raise_error
    end

    # M-2 oracle guard: with no proof the answer must be the 403, never the 422.
    it 'answers 403 (not the interlock 422) when the confirmation is missing' do
      logic = logic_for(colonel, nil, own_handle, session_id: own_sid)

      expect { logic.raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
    end
  end

  describe 'authorization' do
    it 'refuses a non-colonel, revokes nothing and writes NO audit event' do
      expect { logic_for(customer, nil).raise_concerns }.to raise_error(Onetime::Forbidden)
      expect(Onetime::Operations::Sessions::RevokeForCustomer).not_to have_received(:new)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end

    it 'records no event of its own on success — the op owns the trail' do
      logic = logic_for
      logic.raise_concerns
      logic.process

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end
end
