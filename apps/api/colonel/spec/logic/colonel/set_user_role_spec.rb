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
# INTERLOCKS (#4328) land AFTER the gate, so their 422s cannot be used as a free
# "who is the last colonel" / "is this account me" oracle.
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

  # ---- Interlocks (#4328) ----------------------------------------------------
  describe 'interlocks' do
    let(:colonel_target) do
      instance_double(Onetime::Customer,
        objid: 'cust_target', extid: 'ur_target', email: 'target@example.com',
        obscure_email: 't****@example.com', role: 'colonel', verified?: true,
        updated: 1_700_000_000, exists?: true, anonymous?: false)
    end

    let(:second_colonel) do
      instance_double(Onetime::Customer,
        objid: 'cust_other', role: 'colonel', verified?: true, exists?: true)
    end

    def stub_roster(*colonels)
      allow(Onetime::Customer).to receive(:find_all_by_role).with('colonel').and_return(colonels)
    end

    def demote_logic(confirm_token = 'target@example.com')
      described_class.new(
        strategy_result_for(colonel, confirm_token),
        { 'user_id' => 'ur_target', 'role' => 'customer' },
      )
    end

    it 'refuses self-demotion, naming user_id and the CLI remediation' do
      allow(colonel).to receive_messages(
        email: 'target@example.com', exists?: true, updated: 1, obscure_email: 't****@example.com',
      )
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(colonel)
      allow(Onetime::Customer).to receive(:load).and_return(colonel)

      error = begin
        demote_logic.raise_concerns
      rescue Onetime::FormError => ex
        ex
      end

      expect(error.message).to match(/Cannot demote your own colonel account/)
      expect(error.message).to include('bin/ots customers role demote')
    end

    # The acting colonel's OWN record, resolved as the target. Separate double
    # from `colonel` only so the role gate keeps reading 'colonel' for the
    # actor while the target record under test sits at 'admin'.
    it 'still allows PROMOTING yourself (only demotion is a lockout risk)' do
      own_record = instance_double(Onetime::Customer,
        objid: 'cust_colonel', extid: 'ur_colonel', email: 'target@example.com',
        role: 'admin', exists?: true, anonymous?: false)
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(own_record)
      allow(Onetime::Customer).to receive(:load).and_return(own_record)

      expect { logic_for.raise_concerns }.not_to raise_error
    end

    it 'refuses demoting the last remaining verified colonel' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(colonel_target)
      allow(Onetime::Customer).to receive(:load).and_return(colonel_target)
      stub_roster(colonel_target)

      expect { demote_logic.raise_concerns }
        .to raise_error(Onetime::FormError, /last remaining colonel/)
    end

    it 'allows the demotion once a second active colonel exists' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(colonel_target)
      allow(Onetime::Customer).to receive(:load).and_return(colonel_target)
      stub_roster(colonel_target, second_colonel)

      expect { demote_logic.raise_concerns }.not_to raise_error
    end

    # M-2 oracle guard: with no proof the answer must be the 403, never the 422.
    it 'answers 403 (not the interlock 422) when the confirmation is missing' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(colonel_target)
      allow(Onetime::Customer).to receive(:load).and_return(colonel_target)
      stub_roster(colonel_target)

      expect { demote_logic(nil).raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
    end

    it 'answers 403 (not the interlock 422) when elevation is missing' do
      stub_colonel_elevation(enabled: true, window: 600)
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(colonel_target)
      allow(Onetime::Customer).to receive(:load).and_return(colonel_target)
      stub_roster(colonel_target)

      expect { demote_logic.raise_concerns }.to raise_error(Onetime::ElevationRequired)
    end

    it 'does not read the colonel roster when the target is not a colonel' do
      allow(Onetime::Customer).to receive(:find_all_by_role)
      demote_logic.raise_concerns

      expect(Onetime::Customer).not_to have_received(:find_all_by_role)
    end
  end

  # ---- The identifier bug this package fixes ---------------------------------
  describe 'identifier handling' do
    it 'resolves an EMAIL user_id (sanitize_identifier used to strip @ and .)' do
      logic = described_class.new(
        strategy_result_for(colonel),
        { 'user_id' => 'Target@Example.com', 'role' => 'colonel' },
      )
      logic.raise_concerns

      expect(logic.user_id).to eq('Target@Example.com')
      expect(Onetime::Customer).to have_received(:load_by_extid_or_email).with('target@example.com')
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

    it 'hands the op the acting colonel objid for the self-demotion backstop' do
      logic = logic_for
      logic.raise_concerns
      logic.process

      expect(Auth::Operations::Customers::SetRole).to have_received(:new)
        .with(hash_including(actor_objid: 'cust_colonel'))
    end

    # The op is the backstop for a roster that changed under us; its refusal
    # statuses must become the same 422s, never a reported change.
    it 'maps each op refusal status to its 422' do
      {
        self_demotion: /Cannot demote your own colonel account/,
        last_colonel: /last remaining colonel/,
      }.each do |status, message|
        allow(op).to receive(:call).and_return(
          instance_double(Auth::Operations::Customers::SetRole::Result, status: status),
        )
        logic = logic_for
        logic.raise_concerns

        expect { logic.process }.to raise_error(Onetime::FormError, message)
      end
    end

    it 'raises loudly on a status it does not know' do
      allow(op).to receive(:call).and_return(
        instance_double(Auth::Operations::Customers::SetRole::Result, status: :something_new),
      )
      logic = logic_for
      logic.raise_concerns

      expect { logic.process }.to raise_error(Onetime::FormError, /did not complete/)
    end

    it 'records no audit event of its own (the op owns the trail)' do
      logic = logic_for
      logic.raise_concerns
      logic.process

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end
end
