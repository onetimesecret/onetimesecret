# apps/api/colonel/spec/logic/colonel/purge_user_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# DELETE /api/colonel/users/:user_id — the single most destructive colonel verb.
#
# This adapter owns HTTP concerns only: it resolves the target, refuses the
# obviously-wrong targets, gates the request on the #4326 confirmation, and hands
# the customer to Auth::Operations::Customers::Purge, which owns the teardown AND
# the ColonelAuditEvent (CONTRACT 4 — this class never audits).
#
# What these examples pin, beyond the shared confirmation contract:
#
#   - the confirmation token is the account's EMAIL, an identifier the URL (an
#     extid) does not carry, so a scraped-URL replay needs a second fact;
#   - the self-target interlock runs AFTER the confirmation gate (guard order
#     §0.2): its 422 must not tell an un-confirmed caller whether the account
#     they named is their own.
RSpec.describe ColonelAPI::Logic::Colonel::PurgeUser do
  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel', email: 'colonel@example.com',
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
      role: 'customer', exists?: true, anonymous?: false)
  end

  let(:purge_result) do
    instance_double(Auth::Operations::Customers::Purge::Result, status: :success)
  end

  let(:op) { instance_double(Auth::Operations::Customers::Purge, call: purge_result) }

  # `confirm_token` is where the colonel session auth strategy puts the
  # percent-decoded X-OTS-Confirm header (#4326) — never params.
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
    allow(Auth::Operations::Customers::Purge).to receive(:new).and_return(op)
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

    it 'falls back to the extid for an account with no email address' do
      allow(target).to receive(:email).and_return('')
      expect { logic_for(colonel, 'ur_target').raise_concerns }.not_to raise_error
    end

    it 'purges nothing when the confirmation is refused' do
      expect { logic_for(colonel, nil).raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
      expect(Auth::Operations::Customers::Purge).not_to have_received(:new)
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

    it 'purges nothing when the elevation is refused' do
      stub_colonel_elevation(enabled: true)

      expect { elevated_logic_for({}).raise_concerns }.to raise_error(Onetime::ElevationRequired)
      expect(Auth::Operations::Customers::Purge).not_to have_received(:new)
    end

    # An unelevated caller must not reach the self-target interlock either: it
    # is the last of the three refusals in the guard order, and its 422 is the
    # "is this account me?" oracle §0.2 moved behind proof.
    it 'answers the elevation refusal, not the self-target refusal, when both apply' do
      stub_colonel_elevation(enabled: true)
      allow(target).to receive(:objid).and_return('cust_colonel')

      expect { elevated_logic_for({}).raise_concerns }.to raise_error(Onetime::ElevationRequired)
    end
  end

  describe 'guard order (§0.2): interlocks run after proof' do
    # The self-target 422 is interlock state. Reaching it without a valid
    # confirmation would turn purge into a free "is this account me?" oracle.
    it 'answers the confirmation refusal, not the self-target refusal, when both apply' do
      allow(target).to receive(:objid).and_return('cust_colonel')

      expect { logic_for(colonel, nil).raise_concerns }
        .to raise_error(Onetime::ConfirmationRequired)
    end

    it 'still refuses a confirmed self-purge with a 422' do
      allow(target).to receive(:objid).and_return('cust_colonel')

      expect { logic_for.raise_concerns }
        .to raise_error(Onetime::FormError, /Cannot purge your own account/)
    end
  end

  # ---- Last active colonel interlock (#4328 follow-up) -----------------------
  #
  # Purging the last active colonel deletes the last administrator. Purge is
  # irreversible, so this is a PRE-CHECK (no post-write rollback like the demote/
  # unverify verbs). An unverified colonel-role target is not an active colonel,
  # so purging it is allowed.
  describe 'last active colonel' do
    let(:colonel_victim) do
      instance_double(Onetime::Customer,
        objid: 'cust_last', extid: 'ur_last', email: 'boss@example.com',
        role: 'colonel', verified?: true, exists?: true, anonymous?: false)
    end

    def purge_colonel_logic(victim = colonel_victim, confirm = 'boss@example.com')
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(victim)
      allow(Onetime::Customer).to receive(:load).and_return(victim)
      described_class.new(strategy_result_for(colonel, confirm), { 'user_id' => victim.extid })
    end

    it 'refuses purging the last active colonel and purges nothing' do
      allow(Onetime::Customer).to receive(:find_all_by_role).with('colonel').and_return([colonel_victim])

      expect { purge_colonel_logic.raise_concerns }
        .to raise_error(Onetime::FormError, /last active colonel/i)
      expect(Auth::Operations::Customers::Purge).not_to have_received(:new)
    end

    it 'allows purging a colonel when a second verified colonel exists' do
      second = instance_double(Onetime::Customer,
        objid: 'cust_second', role: 'colonel', verified?: true, exists?: true)
      allow(Onetime::Customer).to receive(:find_all_by_role).with('colonel')
        .and_return([colonel_victim, second])

      expect { purge_colonel_logic.raise_concerns }.not_to raise_error
    end

    it 'allows purging an UNVERIFIED colonel-role account (not an active colonel)' do
      unverified = instance_double(Onetime::Customer,
        objid: 'cust_unver', extid: 'ur_unver', email: 'stale@example.com',
        role: 'colonel', verified?: false, exists?: true, anonymous?: false)

      # verified? == false short-circuits before any roster read.
      expect { purge_colonel_logic(unverified, 'stale@example.com').raise_concerns }.not_to raise_error
    end
  end

  describe 'authorization' do
    it 'refuses a non-colonel before anything else, and writes NO audit event' do
      expect { logic_for(customer).raise_concerns }.to raise_error(Onetime::Forbidden)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end

  describe 'the happy path still works' do
    it 'hands the op the resolved customer and the acting colonel extid' do
      logic = logic_for
      logic.raise_concerns
      data = logic.process

      expect(Auth::Operations::Customers::Purge).to have_received(:new)
        .with(hash_including(customer: target, actor: 'ur_colonel'))
      expect(data[:record][:deleted]).to be true
      expect(data[:record][:extid]).to eq('ur_target')
    end

    it 'records no audit event of its own (the op owns the trail)' do
      logic = logic_for
      logic.raise_concerns
      logic.process

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end
end
