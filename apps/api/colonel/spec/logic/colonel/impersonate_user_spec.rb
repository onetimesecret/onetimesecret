# apps/api/colonel/spec/logic/colonel/impersonate_user_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'
require 'auth/operations/customers/impersonate'

# Adapter-layer coverage only. The marker, the audit event and the guards are
# covered by apps/web/auth/spec/operations/customers/impersonate_spec.rb and
# spec/unit/onetime/session/impersonation_spec.rb. These examples assert what
# THIS adapter owns: the mandatory reason, identifier resolution that is not
# email-blind, the four pre-flight refusals, and the response the console
# navigates on.
RSpec.describe ColonelAPI::Logic::Colonel::ImpersonateUser do
  let(:op) { instance_double(Auth::Operations::Customers::Impersonate) }

  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel',
      role: 'colonel', verified?: true, anonymous?: false)
  end

  let(:target) do
    instance_double(Onetime::Customer,
      objid: 'cust_target', extid: 'ur_target',
      email: 'alice@example.com', exists?: true, anonymous?: false,
      suspended?: false)
  end

  let(:session) { {} }

  let(:strategy_result) do
    double('StrategyResult', session: session, user: colonel,
      auth_method: 'sessionauth', metadata: {}, verified?: true)
  end

  let(:op_result) do
    Auth::Operations::Customers::Impersonate::Result.new(
      status: :started,
      customer: target,
      actor: 'ur_colonel',
      reason: 'ticket #123',
      impersonation_id: 'imp_deadbeefdeadbeef',
      expires_at: 1_756_701_800,
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(target).to receive(:role?).with('colonel').and_return(false)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(target)
    allow(Auth::Operations::Customers::Impersonate).to receive(:new).and_return(op)
    allow(op).to receive(:call).and_return(op_result)
  end

  def logic_for(params = {})
    described_class.new(
      strategy_result,
      { 'user_id' => 'ur_target', 'reason' => 'ticket #123' }.merge(params),
    )
  end

  describe 'the happy path' do
    it 'passes the acting colonel extid, the reason, and the live session to the op' do
      logic = logic_for
      logic.raise_concerns
      logic.process

      expect(Auth::Operations::Customers::Impersonate).to have_received(:new).with(
        customer: target,
        actor: 'ur_colonel',
        reason: 'ticket #123',
        session: session,
      )
    end

    it 'returns the correlation id, the target, the expiry, and a hard-navigation target' do
      logic = logic_for
      logic.raise_concerns
      record = logic.process[:record]

      expect(record).to eq(
        impersonation_id: 'imp_deadbeefdeadbeef',
        target_extid: 'ur_target',
        target_email: 'alice@example.com',
        expires_at: 1_756_701_800,
        redirect: '/',
      )
    end

    # /colonel is blocked for the duration, so the console must leave it.
    it 'redirects out of the admin bundle, not to a console route' do
      logic = logic_for
      logic.raise_concerns

      expect(logic.process[:record][:redirect]).not_to start_with('/colonel')
    end

    it 'never audits — the op owns the event' do
      allow(Onetime::ColonelAuditEvent).to receive(:record)

      logic = logic_for
      logic.raise_concerns
      logic.process

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end

  describe 'reason is mandatory' do
    it 'rejects a missing reason as a form error on the reason field' do
      expect { logic_for('reason' => nil).raise_concerns }
        .to raise_error(OT::FormError, /reason is required/i)
    end

    it 'rejects a whitespace-only reason' do
      expect { logic_for('reason' => "   \n").raise_concerns }
        .to raise_error(OT::FormError, /reason is required/i)
    end

    it 'bounds an oversized reason instead of forwarding it' do
      logic = logic_for('reason' => 'x' * 2_000)
      logic.raise_concerns

      expect(logic.reason.length).to eq(described_class::MAX_REASON_LENGTH)
    end
  end

  describe 'identifier handling' do
    # sanitize_identifier strips '@' and '.', which would make the email arm of
    # the resolver unreachable — the trap AccountIdentifier exists to close.
    it 'keeps an email identifier intact for the resolver' do
      logic = logic_for('user_id' => 'alice@example.com')
      logic.raise_concerns

      expect(logic.user_id).to eq('alice@example.com')
    end

    it 'requires a user id' do
      expect { logic_for('user_id' => '').raise_concerns }
        .to raise_error(OT::FormError, /User ID is required/)
    end

    it '404s an unknown user' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(nil)
      allow(Onetime::Customer).to receive(:load).and_return(nil)

      expect { logic_for.raise_concerns }.to raise_error(Onetime::RecordNotFound)
    end
  end

  describe 'pre-flight refusals' do
    it 'refuses an anonymous target' do
      allow(target).to receive(:anonymous?).and_return(true)

      expect { logic_for.raise_concerns }.to raise_error(OT::FormError, /anonymous/i)
    end

    it 'refuses a colonel target' do
      allow(target).to receive(:role?).with('colonel').and_return(true)

      expect { logic_for.raise_concerns }.to raise_error(OT::FormError, /colonel account/i)
    end

    it 'refuses a suspended target' do
      allow(target).to receive(:suspended?).and_return(true)

      expect { logic_for.raise_concerns }.to raise_error(OT::FormError, /suspended/i)
    end
  end

  describe 'op refusals reaching the adapter' do
    # raise_concerns already rejected each of these, so getting here means the
    # target changed underneath us — a 422, never a 500.
    {
      'AlreadyImpersonating' => 'already impersonating',
      'PrivilegedTarget' => 'colonel-role',
      'SuspendedTarget' => 'suspended',
      'AnonymousTarget' => 'anonymous',
      'MissingReason' => 'reason',
    }.each do |error_name, message|
      it "maps #{error_name} to a form error" do
        error = Auth::Operations::Customers::Impersonate.const_get(error_name)
        allow(op).to receive(:call).and_raise(error, message)

        logic = logic_for
        logic.raise_concerns

        expect { logic.process }.to raise_error(OT::FormError, message)
      end
    end
  end
end
