# apps/api/colonel/spec/logic/colonel/destructive_budget_order_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# WHERE the tight colonel:destructive bucket is charged (#4329) — step 5 of the
# guard-order contract, the LAST line of raise_concerns.
#
# This is a regression guard, not a feature test. Charging the destructive budget
# FIRST is the obvious implementation and it is wrong twice over:
#
#   1. The console's designed flow is attempt -> 403 elevation_required ->
#      elevate -> retry. A charge before the elevation check bills that ONE
#      operator action TWICE, so a 10/300s bucket really admits five actions
#      before a 900s lockout.
#   2. Worse adversarially: the bucket is keyed on cust.extid, so an attacker
#      holding the cookie could burn the legitimate colonel's entire destructive
#      budget with ten cheap, unelevated, unconfirmed requests — imposing a
#      15-minute lockout on the operator trying to contain the incident.
#
# So: a request refused for missing elevation, missing/wrong confirmation, or a
# per-verb interlock must consume NOTHING. Volume is still bounded, because the
# broad colonel:mutation bucket is charged in the base constructor before any of
# this runs (rate_limit_hook_spec.rb).
#
# PurgeUser is the subject because it is the only class carrying all three
# refusals — elevation, confirmation and a self-target interlock — over one set
# of params. The equivalent ordering for every other TIER 1 class is pinned
# structurally by spec/unit/colonel/destructive_actions_spec.rb, which asserts
# guard_destructive_action! and charge_destructive_budget! are both present and
# that the charge is last.
#
# The limiter call is spied, not executed: the colonel unit suite runs without
# Redis. The limiter body is proven against real Redis in
# try/unit/security/colonel_rate_limiter_try.rb.
#
# RUN:
#   RACK_ENV=test bundle exec rspec \
#     apps/api/colonel/spec/logic/colonel/destructive_budget_order_spec.rb
RSpec.describe ColonelAPI::Logic::Colonel::PurgeUser do
  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel', email: 'colonel@example.com',
      role: 'colonel', verified?: true, anonymous?: false)
  end

  let(:target) do
    instance_double(Onetime::Customer,
      objid: 'cust_target', extid: 'ur_target', email: 'victim@example.com',
      exists?: true, anonymous?: false)
  end

  let(:purge_result) do
    instance_double(Auth::Operations::Customers::Purge::Result, status: :success)
  end

  let(:op) { instance_double(Auth::Operations::Customers::Purge, call: purge_result) }

  def strategy_result_for(confirm_token, session = {})
    double('StrategyResult', session: session, user: colonel,
      auth_method: 'sessionauth', metadata: { confirm_token: confirm_token, request_method: 'DELETE' })
  end

  # Returns the logic instance with the destructive charge spied, so each example
  # asserts on whether it was called rather than on a Redis counter.
  def spied_logic(confirm_token: 'victim@example.com', session: {})
    logic = described_class.new(strategy_result_for(confirm_token, session), { 'user_id' => 'ur_target' })
    allow(logic).to receive(:enforce_colonel_destructive_limit!)
    logic
  end

  let(:live_session) { elevated_session('ur_colonel') }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(target)
    allow(Onetime::Customer).to receive(:load).and_return(target)
    allow(Auth::Operations::Customers::Purge).to receive(:new).and_return(op)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    stub_colonel_elevation(enabled: true, window: 600)
  end

  describe 'a rejected attempt costs nothing' do
    it 'does not charge when elevation is missing' do
      logic = spied_logic(session: {})

      expect { logic.raise_concerns }.to raise_error(Onetime::ElevationRequired)
      expect(logic).not_to have_received(:enforce_colonel_destructive_limit!)
    end

    it 'does not charge when the elevation window has expired' do
      logic = spied_logic(session: elevated_session('ur_colonel', expires_in: -1))

      expect { logic.raise_concerns }.to raise_error(Onetime::ElevationRequired)
      expect(logic).not_to have_received(:enforce_colonel_destructive_limit!)
    end

    it 'does not charge when the confirmation header is absent' do
      logic = spied_logic(confirm_token: nil, session: live_session)

      expect { logic.raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
      expect(logic).not_to have_received(:enforce_colonel_destructive_limit!)
    end

    it 'does not charge when the confirmation token is wrong' do
      logic = spied_logic(confirm_token: 'not-the-token', session: live_session)

      expect { logic.raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
      expect(logic).not_to have_received(:enforce_colonel_destructive_limit!)
    end

    # The interlock is step 4 — after proof, before the charge. A fully proven
    # request that the business rules refuse still executes nothing, so it still
    # costs nothing.
    it 'does not charge when a per-verb interlock refuses the action' do
      allow(target).to receive(:objid).and_return('cust_colonel')
      logic = spied_logic(session: live_session)

      expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Cannot purge your own account/)
      expect(logic).not_to have_received(:enforce_colonel_destructive_limit!)
    end

    it 'does not charge when the caller is not a colonel at all' do
      not_a_colonel = instance_double(Onetime::Customer,
        objid: 'cust_plain', extid: 'ur_plain', role: 'customer', verified?: true, anonymous?: false)
      logic = described_class.new(
        double('StrategyResult', session: live_session, user: not_a_colonel,
          auth_method: 'sessionauth',
          metadata: { confirm_token: 'victim@example.com', request_method: 'DELETE' }),
        { 'user_id' => 'ur_target' },
      )
      allow(logic).to receive(:enforce_colonel_destructive_limit!)

      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
      expect(logic).not_to have_received(:enforce_colonel_destructive_limit!)
    end
  end

  describe 'an executable attempt is charged exactly once' do
    it 'charges the acting colonel PUBLIC extid when every guard passes' do
      logic = spied_logic(session: live_session)

      logic.raise_concerns

      expect(logic).to have_received(:enforce_colonel_destructive_limit!).once.with('ur_colonel')
    end

    it 'charges in raise_concerns, not in process — a 429 must purge nothing' do
      logic = spied_logic(session: live_session)
      logic.raise_concerns

      expect(Auth::Operations::Customers::Purge).not_to have_received(:new)
    end

    # The bucket subject is the audit `actor`, never an internal objid: an objid
    # in a limiter key would surface it in `bin/ots ratelimit keys`, in
    # GET /ratelimit/inspect and in a `redis-cli --scan`.
    it 'never keys the bucket on an objid' do
      logic = spied_logic(session: live_session)
      logic.raise_concerns

      expect(logic).not_to have_received(:enforce_colonel_destructive_limit!).with('cust_colonel')
    end
  end

  describe 'a 429 from the budget stops the action' do
    it 'raises LimitExceeded out of raise_concerns and purges nothing' do
      logic = described_class.new(
        strategy_result_for('victim@example.com', live_session), { 'user_id' => 'ur_target' },
      )
      allow(logic).to receive(:enforce_colonel_destructive_limit!)
        .and_raise(Onetime::LimitExceeded.new('Too many destructive admin actions.',
          retry_after: 900, max_attempts: 10))

      expect { logic.raise_concerns }.to raise_error(Onetime::LimitExceeded)
      expect(Auth::Operations::Customers::Purge).not_to have_received(:new)
    end

    # LimitExceeded < Forbidden, so AuditedFailure drops it: a throttled caller
    # cannot mint operator-trail events by hammering the gate. Only the
    # cap-REACHING request writes one, and it writes it via .record_security.
    it 'writes no operator-trail audit event' do
      logic = described_class.new(
        strategy_result_for('victim@example.com', live_session), { 'user_id' => 'ur_target' },
      )
      allow(logic).to receive(:enforce_colonel_destructive_limit!)
        .and_raise(Onetime::LimitExceeded.new('nope', retry_after: 900, max_attempts: 10))

      expect { logic.raise_concerns }.to raise_error(Onetime::LimitExceeded)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end
end
