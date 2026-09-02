# spec/unit/onetime/logic/colonel/operator_reason_param_spec.rb
#
# frozen_string_literal: true

# #4338, adapter half: the operator's `reason` has to survive the trip from the
# HTTP request into the op, or the console's new textarea explains nothing.
#
# The op-level contract (what lands in `detail`, and that a blank reason leaves
# the detail byte-identical) is pinned in
# spec/unit/onetime/operations/operator_reason_audit_spec.rb. This file pins the
# THREE things only the adapter can get wrong:
#
#   1. The param is READ and passed to the op as its `reason:` kwarg.
#   2. It is SANITIZED on the way through — HTML stripped, whitespace collapsed,
#      bounded at Onetime::AuditReason::MAX_LENGTH — so free operator text
#      cannot carry markup into an operator-facing console, and cannot exceed
#      what the audit model will store without truncating.
#   3. Blank stays ABSENT (`nil`, never `''`), on every verb.
#
# One reader (ColonelAPI::Logic::Base#operator_reason_param) serves every
# destructive colonel adapter, so a POST verb and a DELETE verb are enough to
# cover both wire shapes: a POST reads it from the body, a DELETE from the query
# string (DELETE bodies are not reliably parsed across this stack). `params`
# merges both server-side, which is exactly why one reader can serve them.
#
# Run: pnpm run test:rspec spec/unit/onetime/logic/colonel/operator_reason_param_spec.rb

require 'spec_helper'
require 'colonel/application'

RSpec.describe 'colonel destructive verbs accept an operator reason (#4338)' do
  let(:colonel) do
    double(
      'Customer',
      extid: 'ur_colonel_public', role: 'colonel', objid: 'cust-obj-1',
      email: 'colonel@example.com', anonymous?: false, verified?: true,
    )
  end

  # Both verbs are TIER 1 destructive (#4326): raise_concerns demands the
  # target's confirmation token via the X-OTS-Confirm header before process
  # ever runs. The reason rides BESIDE that token, never instead of it. The
  # target doubles stub no :email, so account_confirm_token falls back to the
  # extid — 'ur_target' is the expected token for both describes below.
  let(:strategy_result) do
    double(
      'StrategyResult',
      session: {}, user: colonel, auth_method: 'sessionauth',
      metadata: { ip: '127.0.0.1', confirm_token: 'ur_target' },
    )
  end

  # -- POST verb: the reason arrives in the body ------------------------------
  describe ColonelAPI::Logic::Colonel::SetUserRole do
    let(:target) do
      double('Customer', extid: 'ur_target', objid: 'obj-t', role: 'customer',
                         exists?: true, anonymous?: false,
                         obscure_email: 't***@e***.com', updated: 1)
    end
    let(:op) do
      instance_double(
        Auth::Operations::Customers::SetRole,
        call: Auth::Operations::Customers::SetRole::Result.new(
          status: :success, customer: target, from: 'customer', to: 'admin',
        ),
      )
    end

    before do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(target)
      allow(Auth::Operations::Customers::SetRole).to receive(:new).and_return(op)
    end

    def run(params)
      logic = described_class.new(strategy_result, params)
      logic.process_params
      logic.raise_concerns
      logic.process
    end

    it 'passes the reason to the op' do
      run('user_id' => 'ur_target', 'role' => 'admin', 'reason' => 'promoted per ticket 88')

      expect(Auth::Operations::Customers::SetRole).to have_received(:new).with(
        customer: target,
        role: 'admin',
        actor: 'ur_colonel_public',
        actor_objid: 'cust-obj-1',
        reason: 'promoted per ticket 88',
      )
    end

    it 'passes nil — never an empty string — when the param is blank or absent' do
      run('user_id' => 'ur_target', 'role' => 'admin', 'reason' => '   ')
      expect(Auth::Operations::Customers::SetRole)
        .to have_received(:new).with(hash_including(reason: nil))

      run('user_id' => 'ur_target', 'role' => 'admin')
      expect(Auth::Operations::Customers::SetRole)
        .to have_received(:new).twice.with(hash_including(reason: nil))
    end

    it 'strips markup and collapses whitespace out of the free text' do
      run(
        'user_id' => 'ur_target', 'role' => 'admin',
        'reason' => "<b>spam</b>\n\n  reports",
      )

      expect(Auth::Operations::Customers::SetRole)
        .to have_received(:new).with(hash_including(reason: 'spam reports'))
    end

    it 'bounds the reason at AuditReason::MAX_LENGTH so the trail never truncates it' do
      run('user_id' => 'ur_target', 'role' => 'admin', 'reason' => 'x' * 400)

      expect(Auth::Operations::Customers::SetRole).to have_received(:new).with(
        hash_including(reason: 'x' * Onetime::AuditReason::MAX_LENGTH),
      )
      expect(Onetime::AuditReason::MAX_LENGTH)
        .to be < Onetime::ColonelAuditEvent::MAX_DETAIL_VALUE_LENGTH
    end
  end

  # -- DELETE verb: the reason arrives on the query string ---------------------
  describe ColonelAPI::Logic::Colonel::PurgeUser do
    let(:target) do
      # role feeds the last-colonel interlock in raise_concerns; a plain
      # customer short-circuits it.
      double('Customer', extid: 'ur_target', objid: 'obj-t', custid: 'cust-t',
                         anonymous?: false, exists?: true, role: 'customer')
    end
    let(:op) do
      instance_double(
        Auth::Operations::Customers::Purge,
        call: Auth::Operations::Customers::Purge::Result.new(
          status: :success, extid: 'ur_target', custid: 'cust-t',
        ),
      )
    end

    before do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(target)
      allow(Auth::Operations::Customers::Purge).to receive(:new).and_return(op)
    end

    def run(params)
      logic = described_class.new(strategy_result, params)
      logic.process_params
      logic.raise_concerns
      logic.process
    end

    # Rack merges the query string into `params`, so the DELETE path reads the
    # reason through the SAME Base#operator_reason_param as the POST above.
    it 'passes the query-string reason to the op' do
      run('user_id' => 'ur_target', 'reason' => 'GDPR erasure request #4412')

      expect(Auth::Operations::Customers::Purge).to have_received(:new).with(
        customer: target,
        actor: 'ur_colonel_public',
        reason: 'GDPR erasure request #4412',
      )
    end

    it 'passes nil when no reason rides the request' do
      run('user_id' => 'ur_target')

      expect(Auth::Operations::Customers::Purge)
        .to have_received(:new).with(hash_including(reason: nil))
    end
  end
end
