# apps/api/colonel/spec/logic/colonel/delete_session_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# DELETE /api/colonel/sessions/:session_handle. The route used to take the raw
# session id — the user's live `onetime.session` cookie value — straight off the
# console listing (#4330). These examples pin what this adapter owns now:
#
#   - the handle resolves to a sid SERVER-SIDE, and the OP is handed that sid;
#   - the response echoes the handle and nothing else identifying;
#   - an unresolvable handle 404s before anything is deleted;
#   - the adapter records NO audit event of its own — Sessions::Delete owns the
#     trail (CONTRACT 4), and a rejection records nothing at all.
#
# The audit target itself (a handle, never the sid) is proven against a real
# write in try/unit/operations/sessions/delete_session_audit_try.rb.
RSpec.describe ColonelAPI::Logic::Colonel::DeleteSession do
  let(:handle) { '0123456789abcdef0123456789abcdef' }
  let(:session_id) { 'b' * 64 }

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

  let(:delete_result) do
    Onetime::Operations::Sessions::Delete::Result.new(
      status: :deleted, session_id: session_id, key: "session:#{session_id}",
    )
  end

  let(:delete_op) do
    instance_double(Onetime::Operations::Sessions::Delete, call: delete_result)
  end

  # The confirmation token (#4326) is the session OWNER, read off the inspected
  # payload — the handle in the URL cannot be transformed into it.
  let(:owner_email) { 'owner@example.com' }

  let(:inspect_result) do
    Onetime::Operations::Sessions::Inspect::Result.new(
      found: true, session_id: session_id, key: "session:#{session_id}", ttl: 3600,
      data: { 'email' => owner_email, 'external_id' => 'ur_owner' },
    )
  end

  # `confirm_token` is where the colonel session auth strategy puts the
  # percent-decoded X-OTS-Confirm header — never params.
  def strategy_result_for(user, confirm_token = owner_email, session = {})
    double('StrategyResult', session: session, user: user,
      auth_method: 'sessionauth', metadata: { confirm_token: confirm_token })
  end

  def logic_for(user = colonel, params = { 'session_handle' => handle })
    described_class.new(strategy_result_for(user), params)
  end

  def stub_resolution(sid: session_id, scan_capped: false)
    allow(Onetime::Operations::Sessions::Store).to receive(:resolve_handle)
      .and_return([sid, scan_capped])
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Familia).to receive(:dbclient).and_return(double('Redis'))
    allow(Onetime::Operations::Sessions::Delete).to receive(:new).and_return(delete_op)
    allow(Onetime::Operations::Sessions::Inspect).to receive(:new).and_return(
      instance_double(Onetime::Operations::Sessions::Inspect, call: inspect_result),
    )
    allow(Onetime::ColonelAuditEvent).to receive(:record)
  end

  # ---- Server-side confirmation (#4326) --------------------------------------

  describe 'confirmation' do
    let(:expected_confirm_token) { owner_email }

    def confirmed_logic_for(confirm_token)
      described_class.new(
        strategy_result_for(colonel, confirm_token),
        { 'session_handle' => handle },
      )
    end

    before { stub_resolution }

    it_behaves_like 'a confirmed colonel action'

    it 'falls back to the owner external id when the payload carries no email' do
      allow(Onetime::Operations::Sessions::Inspect).to receive(:new).and_return(
        instance_double(
          Onetime::Operations::Sessions::Inspect,
          call: Onetime::Operations::Sessions::Inspect::Result.new(
            found: true, session_id: session_id, key: "session:#{session_id}", ttl: 1,
            data: { 'external_id' => 'ur_owner' },
          ),
        ),
      )

      expect { confirmed_logic_for('ur_owner').raise_concerns }.not_to raise_error
    end

    it 'falls back to the handle for an anonymous session, and says so' do
      allow(Onetime::Operations::Sessions::Inspect).to receive(:new).and_return(
        instance_double(
          Onetime::Operations::Sessions::Inspect,
          call: Onetime::Operations::Sessions::Inspect::Result.new(
            found: true, session_id: session_id, key: "session:#{session_id}", ttl: 1,
            data: { 'csrf' => 'tok' },
          ),
        ),
      )

      expect { confirmed_logic_for(handle).raise_concerns }.not_to raise_error

      error = begin
        confirmed_logic_for(nil).raise_concerns
      rescue Onetime::ConfirmationRequired => ex
        ex
      end
      expect(error.message).to include('session handle')
    end
  end

  # ---- Step-up (sudo) window (#4327) -----------------------------------------
  describe 'elevation' do
    let(:expected_confirm_token) { owner_email }

    def elevated_logic_for(session, confirm_token = expected_confirm_token)
      described_class.new(
        strategy_result_for(colonel, confirm_token, session),
        { 'session_handle' => handle },
      )
    end

    before { stub_resolution }

    it_behaves_like 'an elevated colonel action'
  end

  describe 'handle resolution' do
    it 'hands the OP the resolved sid, never the submitted handle' do
      stub_resolution
      logic = logic_for
      logic.raise_concerns
      logic.process

      expect(Onetime::Operations::Sessions::Delete).to have_received(:new)
        .with(session_id: session_id, actor: 'ur_colonel')
    end

    it 'passes the optional owner hint through to the resolver' do
      stub_resolution
      logic_for(colonel, { 'session_handle' => handle, 'user_id' => 'ur_alice' })
        .raise_concerns

      expect(Onetime::Operations::Sessions::Store).to have_received(:resolve_handle)
        .with(anything, handle, owner_hint: 'ur_alice')
    end

    it '404s and deletes nothing when the handle resolves to no live session' do
      stub_resolution(sid: nil)

      expect { logic_for.raise_concerns }.to raise_error(Onetime::RecordNotFound)
      expect(Onetime::Operations::Sessions::Delete).not_to have_received(:new)
    end

    it '404s on a malformed handle rather than 422 (same answer as unknown)' do
      allow(Onetime::Operations::Sessions::Store).to receive(:resolve_handle).and_call_original

      expect { logic_for(colonel, { 'session_handle' => 'nope' }).raise_concerns }
        .to raise_error(Onetime::RecordNotFound)
    end

    it '422s only when no handle was supplied at all' do
      expect { logic_for(colonel, { 'session_handle' => '' }) }
        .to raise_error(Onetime::FormError)
    end
  end

  describe 'response shape' do
    subject(:response) do
      stub_resolution
      logic = logic_for
      logic.raise_concerns
      logic.process
    end

    it 'echoes the handle the caller sent' do
      expect(response[:record][:session_handle]).to eq(handle)
    end

    it 'reports the delete' do
      expect(response[:record][:deleted]).to be true
      expect(response[:details][:message]).to eq('Session revoked successfully')
    end

    it 'never leaks the raw sid anywhere in the returned hash' do
      expect(response.to_s).not_to include(session_id)
      expect(response[:record]).not_to have_key(:session_id)
    end

    it 'reports deleted:false when the op found nothing left to remove' do
      stub_resolution
      allow(delete_op).to receive(:call).and_return(
        Onetime::Operations::Sessions::Delete::Result.new(
          status: :not_found, session_id: session_id, key: nil,
        ),
      )
      logic = logic_for
      logic.raise_concerns

      expect(logic.process[:record][:deleted]).to be false
    end
  end

  # ---- Self-target interlock (#4328) -----------------------------------------
  #
  # Revoking the session you are working in signs YOU out mid-incident. The
  # comparison is over HANDLES, so the raw bearer sid never meets
  # attacker-supplied input; and it runs at step 4, after the confirmation gate,
  # so the 422 is not a free "is this handle mine?" oracle over the listing.
  describe 'self-target' do
    # A Rack SessionId: #public_id is the cookie value the handle is digested
    # from. safe_session_id reads it off `sess`.
    let(:own_sid) { 'c' * 64 }
    let(:own_handle) { Onetime::SessionMetadata.handle_for(own_sid) }

    def own_session_logic(handle_param, confirm_token = owner_email)
      described_class.new(
        double('StrategyResult',
          session: double('Session', id: double('SessionId', public_id: own_sid)),
          user: colonel, auth_method: 'sessionauth',
          metadata: { confirm_token: confirm_token }),
        { 'session_handle' => handle_param },
      )
    end

    before { stub_resolution }

    it 'refuses revoking your own active session, naming session_handle' do
      error = begin
        own_session_logic(own_handle).raise_concerns
      rescue Onetime::FormError => ex
        ex
      end

      expect(error.message).to match(/Cannot revoke your own active session/)
      expect(Onetime::Operations::Sessions::Delete).not_to have_received(:new)
    end

    it 'proceeds for any other handle' do
      expect { own_session_logic(handle).raise_concerns }.not_to raise_error
    end

    it 'does not raise when the request session has no resolvable id' do
      expect { logic_for.raise_concerns }.not_to raise_error
    end

    # M-2 oracle guard: without the confirmation the answer must be the 403.
    it 'answers 403 (not the interlock 422) when the confirmation is missing' do
      expect { own_session_logic(own_handle, nil).raise_concerns }
        .to raise_error(Onetime::ConfirmationRequired)
    end
  end

  describe 'authorization' do
    it 'refuses a non-colonel, deletes nothing and writes NO audit event' do
      stub_resolution
      logic = logic_for(customer)

      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
      expect(Onetime::Operations::Sessions::Delete).not_to have_received(:new)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end

    it 'records no event of its own on success — the op owns the trail' do
      stub_resolution
      logic = logic_for
      logic.raise_concerns
      logic.process

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end
end
