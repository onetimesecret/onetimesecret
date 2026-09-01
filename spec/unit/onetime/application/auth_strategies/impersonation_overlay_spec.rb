# spec/unit/onetime/application/auth_strategies/impersonation_overlay_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/application/auth_strategies/session_auth_strategy'
require 'onetime/helpers/session_helpers'

# Where the overlay actually bites.
#
# Three call sites resolve identity from `session['external_id']`, and all three
# now go through Onetime::SessionImpersonation.resolve. These examples pin the
# two properties that make the feature safe rather than merely working:
#
#   1. The AUTHORITATIVE resolution (BaseSessionAuthStrategy) yields the TARGET
#      as strategy_result.user AND as user_roles — which is what makes every
#      role=colonel route 403 for the duration, with no extra guard.
#   2. The PRINCIPAL's own gates (suspension, credential watermark) still judge
#      the operator, and they run BEFORE the overlay. A suspended colonel loses
#      the entire session, not just the overlay.
RSpec.describe 'impersonation overlay at the identity call sites' do
  let(:now) { 1_756_700_000 }

  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', custid: 'ops@example.com', extid: 'ur_colonel',
      email: 'ops@example.com', role: 'colonel', verified?: true,
      suspended?: false, anonymous?: false, last_password_update: 0)
  end

  let(:target) do
    instance_double(Onetime::Customer,
      objid: 'cust_target', custid: 'alice@example.com', extid: 'ur_target',
      email: 'alice@example.com', role: 'customer', verified?: true,
      suspended?: false, anonymous?: false, last_password_update: 0)
  end

  let(:marker) do
    {
      'id' => 'imp_deadbeefdeadbeef',
      'target_extid' => 'ur_target',
      'target_email' => 'alice@example.com',
      'reason' => 'ticket #123',
      'started_at' => now,
      'expires_at' => now + Onetime::SessionImpersonation::TTL,
    }
  end

  let(:session) do
    {
      'authenticated' => true,
      'authenticated_at' => now,
      'external_id' => 'ur_colonel',
      'role' => 'colonel',
      Onetime::SessionImpersonation::SESSION_KEY => marker,
    }
  end

  before do
    allow(Familia).to receive(:now).and_return(now)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(OT).to receive(:ld)
    allow(colonel).to receive(:role?).with('colonel').and_return(true)
    allow(target).to receive(:role?).with('colonel').and_return(false)
  end

  describe Onetime::Application::AuthStrategies::SessionAuthStrategy do
    subject(:strategy) { described_class.new }

    let(:env) do
      {
        'rack.session' => session,
        'REMOTE_ADDR' => '127.0.0.1',
        'HTTP_USER_AGENT' => 'Test/1.0',
      }
    end

    before do
      # The principal is loaded from external_id; the resolver loads the target.
      allow(Onetime::Customer).to receive(:load_by_extid_or_email)
        .with('ur_colonel').and_return(colonel)
      allow(Onetime::Customer).to receive(:load_by_extid_or_email)
        .with('ur_target').and_return(target)
      allow(target).to receive(:exists?).and_return(true)
      allow(strategy).to receive(:load_organization_context).and_return({})
    end

    it 'authenticates as the TARGET' do
      result = strategy.authenticate(env, nil)

      expect(result).to be_a(Otto::Security::Authentication::StrategyResult)
      expect(result.user).to be(target)
    end

    # This is what makes /api/colonel 403 while impersonating, with no
    # impersonation-specific code in the router.
    it 'reports the TARGET role to Otto, not the colonel role' do
      result = strategy.authenticate(env, nil)

      expect(result.metadata[:user_roles]).to eq(['customer'])
    end

    it 'authenticates as the colonel once the overlay is gone' do
      session.delete(Onetime::SessionImpersonation::SESSION_KEY)

      expect(strategy.authenticate(env, nil).user).to be(colonel)
    end

    it 'rejects the whole session when the PRINCIPAL is suspended' do
      allow(colonel).to receive(:suspended?).and_return(true)

      result = strategy.authenticate(env, nil)

      expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
      expect(result.failure_reason).to include('ACCOUNT_SUSPENDED')
    end

    it 'rejects the whole session when the PRINCIPAL credentials were rotated' do
      allow(colonel).to receive(:last_password_update).and_return(now + 10)

      result = strategy.authenticate(env, nil)

      expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
      expect(result.failure_reason).to include('SESSION_STALE_CREDENTIALS')
    end

    # A suspended TARGET ends only the overlay: the operator keeps their
    # session and lands back on their own account.
    it 'falls back to the colonel when the TARGET becomes suspended' do
      allow(target).to receive(:suspended?).and_return(true)

      result = strategy.authenticate(env, nil)

      expect(result.user).to be(colonel)
      expect(result.metadata[:user_roles]).to eq(['colonel'])
      expect(session).not_to have_key(Onetime::SessionImpersonation::SESSION_KEY)
    end
  end

  describe Onetime::Helpers::SessionHelpers do
    let(:helper_class) do
      Class.new do
        include Onetime::Helpers::SessionHelpers

        attr_reader :session

        def initialize(session)
          @session = session
        end
      end
    end

    subject(:helper) { helper_class.new(session) }

    before do
      allow(helper).to receive(:session_auth_enforced?).and_return(true)
      allow(Onetime::Customer).to receive(:find_by_extid).with('ur_colonel').and_return(colonel)
      allow(Onetime::Customer).to receive(:load_by_extid_or_email)
        .with('ur_target').and_return(target)
      allow(target).to receive(:exists?).and_return(true)
    end

    it 'returns the TARGET as the current customer' do
      expect(helper.current_customer).to be(target)
    end

    # The cache backs has_role?/colonel?, which load no Customer. Stamping the
    # target's role here would demote the operator for the rest of the session
    # and survive the stop.
    it 'does NOT overwrite the cached colonel role with the target role' do
      helper.current_customer

      expect(session['role']).to eq('colonel')
    end

    it 'refreshes the cached role from the principal when not impersonating' do
      session.delete(Onetime::SessionImpersonation::SESSION_KEY)
      session['role'] = 'customer'

      expect(helper.current_customer).to be(colonel)
      expect(session['role']).to eq('colonel')
    end
  end
end
