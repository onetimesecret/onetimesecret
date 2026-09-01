# apps/api/colonel/spec/logic/colonel/revoke_all_customer_sessions_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# POST /api/colonel/users/:user_id/sessions/revoke-all — logs a customer out of
# EVERY device, so TIER 1 (#4326).
#
# This adapter is deliberately thin: Onetime::Operations::Sessions::RevokeAllForCustomer
# owns the purge and the single ColonelAuditEvent (CONTRACT 4). The account is
# resolved here ONLY to name the confirmation token — it is not (yet) a 404
# guard, because the op is idempotent on an unknown custid. P4 (#4328) adds the
# existence check and the self-target interlock between that resolve and the gate.
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

    # The expected token must never be blank — that is a 500 by design — so an
    # identifier that resolves to nothing falls back to what the caller sent.
    it 'falls back to the submitted identifier when the account does not resolve' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)
      allow(Onetime::Customer).to receive(:load).and_return(nil)

      expect { logic_for(colonel, 'ur_target').raise_concerns }.not_to raise_error
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

  describe 'the happy path still works' do
    it 'hands the op the custid and the acting colonel extid' do
      logic = logic_for
      logic.raise_concerns
      data = logic.process

      expect(Onetime::Operations::Sessions::RevokeAllForCustomer).to have_received(:new)
        .with(hash_including(custid: 'ur_target', actor: 'ur_colonel'))
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
