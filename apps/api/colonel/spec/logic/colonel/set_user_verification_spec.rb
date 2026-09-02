# apps/api/colonel/spec/logic/colonel/set_user_verification_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# POST /api/colonel/users/:user_id/{verify,unverify} — one shared base, two arms,
# and only ONE of them is gated (#4326, TIER 2).
#
# UNVERIFY strips colonel eligibility: has_system_role? refuses every elevated
# role to an unverified account ("Defense in depth: System roles require email
# verification"), so an un-gated unverify is a route to leaving an install with
# zero working colonels. VERIFY is the restorative arm and stays a one-click
# operator action.
#
# The split is `return if verified_target` inside SetUserVerificationBase, which
# is exactly the asymmetry these examples pin — a refactor that hoists the guard
# above that line would silently gate the recovery path. It now guards the
# #4328 interlocks too.
RSpec.describe ColonelAPI::Logic::Colonel::UnverifyUser do
  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel',
      role: 'colonel', verified?: true, anonymous?: false)
  end

  let(:target) do
    instance_double(Onetime::Customer,
      objid: 'cust_target', extid: 'ur_target', email: 'target@example.com',
      obscure_email: 't****@example.com', role: 'customer', verified?: false,
      updated: 1_700_000_000, exists?: true, anonymous?: false)
  end

  let(:op) do
    instance_double(Auth::Operations::Customers::SetVerification, call: :success)
  end

  # `confirm_token` is where the colonel session auth strategy puts the
  # percent-decoded X-OTS-Confirm header — never params.
  def strategy_result_for(confirm_token = 'target@example.com')
    double('StrategyResult', session: {}, user: colonel,
      auth_method: 'sessionauth', metadata: { confirm_token: confirm_token })
  end

  def logic_for(klass, confirm_token)
    klass.new(strategy_result_for(confirm_token), { 'user_id' => 'ur_target' })
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(target)
    allow(Onetime::Customer).to receive(:load).and_return(target)
    allow(Auth::Operations::Customers::SetVerification).to receive(:new).and_return(op)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
  end

  describe 'unverify is gated' do
    let(:expected_confirm_token) { 'target@example.com' }

    def confirmed_logic_for(confirm_token)
      logic_for(described_class, confirm_token)
    end

    it_behaves_like 'a confirmed colonel action'

    it 'unverifies nothing when the confirmation is refused' do
      expect { confirmed_logic_for(nil).raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
      expect(Auth::Operations::Customers::SetVerification).not_to have_received(:new)
    end
  end

  describe 'verify is NOT gated (the restorative arm)' do
    it 'needs no confirmation' do
      logic = logic_for(ColonelAPI::Logic::Colonel::VerifyUser, nil)

      expect { logic.raise_concerns }.not_to raise_error
    end

    it 'still reaches the op' do
      logic = logic_for(ColonelAPI::Logic::Colonel::VerifyUser, nil)
      logic.raise_concerns
      logic.process

      expect(Auth::Operations::Customers::SetVerification).to have_received(:new)
        .with(hash_including(verified: true, actor: 'ur_colonel'))
    end
  end

  # ---- Interlocks (#4328, review B-1) ----------------------------------------
  #
  # Unverifying strips colonel eligibility, so an attacker refused a demotion by
  # RoleSupport.last_colonel? would otherwise just call unverify instead. Both
  # refusals run at STEP 4 — after the confirmation gate — so their 422s cannot
  # be used as a "who is the last colonel" oracle by a caller holding only the
  # cookie.
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

    it 'refuses unverifying your own account, naming user_id' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(colonel)
      allow(Onetime::Customer).to receive(:load).and_return(colonel)
      allow(colonel).to receive_messages(email: 'target@example.com', exists?: true)
      stub_roster(colonel)

      expect { logic_for(described_class, 'target@example.com').raise_concerns }
        .to raise_error(Onetime::FormError, /Cannot unverify your own account/)
    end

    it 'refuses unverifying the last remaining verified colonel' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(colonel_target)
      allow(Onetime::Customer).to receive(:load).and_return(colonel_target)
      stub_roster(colonel_target)

      expect { logic_for(described_class, 'target@example.com').raise_concerns }
        .to raise_error(Onetime::FormError, /last remaining colonel/)
    end

    it 'allows it once a second active colonel exists' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(colonel_target)
      allow(Onetime::Customer).to receive(:load).and_return(colonel_target)
      stub_roster(colonel_target, second_colonel)

      expect { logic_for(described_class, 'target@example.com').raise_concerns }.not_to raise_error
    end

    # M-2 oracle guard: with no confirmation the answer must be the 403, never
    # the interlock 422 — otherwise the refusal itself discloses the roster.
    it 'answers 403 (not the interlock 422) when the confirmation is missing' do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(colonel_target)
      allow(Onetime::Customer).to receive(:load).and_return(colonel_target)
      stub_roster(colonel_target)

      expect { logic_for(described_class, nil).raise_concerns }
        .to raise_error(Onetime::ConfirmationRequired)
    end

    it 'does not run the roster read on the verify arm' do
      allow(Onetime::Customer).to receive(:find_all_by_role)
      logic_for(ColonelAPI::Logic::Colonel::VerifyUser, nil).raise_concerns

      expect(Onetime::Customer).not_to have_received(:find_all_by_role)
    end
  end

  describe 'the happy path still works' do
    it 'hands the op verified: false, the acting colonel extid and its objid' do
      logic = logic_for(described_class, 'target@example.com')
      logic.raise_concerns
      logic.process

      expect(Auth::Operations::Customers::SetVerification).to have_received(:new)
        .with(hash_including(verified: false, actor: 'ur_colonel', actor_objid: 'cust_colonel'))
    end

    # The op is the backstop: if the roster changed between raise_concerns and
    # the write, its refusal status must become the same 422, never a reported
    # change that did not happen.
    it 'maps an op-level refusal status to a 422' do
      allow(op).to receive(:call).and_return(:last_colonel)
      logic = logic_for(described_class, 'target@example.com')
      logic.raise_concerns

      expect { logic.process }.to raise_error(Onetime::FormError, /last remaining colonel/)
    end

    it 'raises loudly on a status it does not know' do
      allow(op).to receive(:call).and_return(:something_new)
      logic = logic_for(described_class, 'target@example.com')
      logic.raise_concerns

      expect { logic.process }.to raise_error(Onetime::FormError, /did not complete/)
    end
  end
end
