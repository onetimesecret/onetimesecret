# apps/api/colonel/spec/logic/colonel/set_user_role_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# POST /api/colonel/users/:user_id/role — privilege-granting, so TIER 1 (#4326).
#
# This adapter owns HTTP concerns only; Auth::Operations::Customers::SetRole owns
# the mutation and the ColonelAuditEvent (CONTRACT 4).
#
# The role ENUM check is shape validation (guard-order step 2) and therefore
# still runs before the confirmation gate: the caller supplied the role, so
# rejecting an unknown one discloses nothing. The self-demotion and last-colonel
# INTERLOCKS (#4328) land after the gate — P4 extends this file.
RSpec.describe ColonelAPI::Logic::Colonel::SetUserRole do
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
      objid: 'cust_target', extid: 'ur_target', email: 'target@example.com',
      obscure_email: 't****@example.com', role: 'admin', updated: 1_700_000_000,
      exists?: true, anonymous?: false)
  end

  let(:op) do
    instance_double(Auth::Operations::Customers::SetRole,
      call: instance_double(Auth::Operations::Customers::SetRole::Result, status: :success))
  end

  # `confirm_token` is where the colonel session auth strategy puts the
  # percent-decoded X-OTS-Confirm header — never params.
  def strategy_result_for(user, confirm_token = 'target@example.com', session = {})
    double('StrategyResult', session: session, user: user,
      auth_method: 'sessionauth', metadata: { confirm_token: confirm_token })
  end

  def logic_for(user = colonel, confirm_token = 'target@example.com', params = {})
    described_class.new(
      strategy_result_for(user, confirm_token),
      { 'user_id' => 'ur_target', 'role' => 'colonel' }.merge(params),
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(target)
    allow(Onetime::Customer).to receive(:load).and_return(target)
    allow(Auth::Operations::Customers::SetRole).to receive(:new).and_return(op)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
  end

  describe 'confirmation (#4326)' do
    let(:expected_confirm_token) { 'target@example.com' }

    def confirmed_logic_for(confirm_token)
      logic_for(colonel, confirm_token)
    end

    it_behaves_like 'a confirmed colonel action'

    it 'does not accept the extid the URL already carried' do
      expect { logic_for(colonel, 'ur_target').raise_concerns }
        .to raise_error(Onetime::ConfirmationRequired)
    end

    it 'changes no role when the confirmation is refused' do
      expect { logic_for(colonel, nil).raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
      expect(Auth::Operations::Customers::SetRole).not_to have_received(:new)
    end
  end

  # ---- Step-up (sudo) window (#4327) -----------------------------------------
  describe 'elevation' do
    let(:expected_confirm_token) { 'target@example.com' }

    def elevated_logic_for(session, confirm_token = expected_confirm_token)
      described_class.new(
        strategy_result_for(colonel, confirm_token, session),
        { 'user_id' => 'ur_target', 'role' => 'colonel' },
      )
    end

    it_behaves_like 'an elevated colonel action'
  end

  describe 'guard order (§0.2)' do
    it 'rejects an unknown role BEFORE the confirmation gate (shape, not secret)' do
      expect { logic_for(colonel, nil, 'role' => 'emperor').raise_concerns }
        .to raise_error(Onetime::FormError, /Invalid role/)
    end

    it 'rejects a non-colonel before either' do
      expect { logic_for(customer, nil).raise_concerns }.to raise_error(Onetime::Forbidden)
    end
  end

  describe 'the happy path still works' do
    it 'hands the op the resolved customer, the role, and the colonel extid' do
      logic = logic_for
      logic.raise_concerns
      data = logic.process

      expect(Auth::Operations::Customers::SetRole).to have_received(:new)
        .with(hash_including(customer: target, role: 'colonel', actor: 'ur_colonel'))
      expect(data[:details][:changed]).to be true
    end

    it 'records no audit event of its own (the op owns the trail)' do
      logic = logic_for
      logic.raise_concerns
      logic.process

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end
end
