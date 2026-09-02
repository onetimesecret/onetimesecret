# spec/unit/onetime/application/auth_strategies/base_session_auth_strategy_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/application/auth_strategies'

# The ORDER of the checks in BaseSessionAuthStrategy#authenticate, and what the
# #4331 admin-surface bound does when it refuses.
#
# The bound's own decision table is
# spec/unit/onetime/application/auth_strategies/admin_session_lifetime_spec.rb.
# What is asserted here is only what the wiring owns: that the check runs AFTER
# the credential watermark and BEFORE additional_checks, that the failure carries
# the [ADMIN_SESSION_EXPIRED] marker the console branches on, and that a refused
# request stamps the env flag that stops TrackMetadata from counting it as
# activity.
RSpec.describe Onetime::Application::AuthStrategies::BaseSessionAuthStrategy do
  let(:lifetime) { Onetime::Application::AuthStrategies::AdminSessionLifetime }

  # A concrete subclass: the base class is abstract (auth_method_name is nil) and
  # `additional_checks` is the hook whose ORDERING relative to the new bound is
  # the point of this file.
  let(:strategy_class) do
    Class.new(described_class) do
      @auth_method_name = 'sessionauth'

      attr_reader :additional_checks_ran

      def additional_checks(_cust, _env)
        @additional_checks_ran = true
        nil
      end
    end
  end

  let(:strategy) { strategy_class.new }

  let(:cust) do
    instance_double(
      Onetime::Customer,
      objid: 'cust_1',
      extid: 'ur_abc',
      role: 'colonel',
      suspended?: false,
      last_password_update: nil,
    )
  end

  let(:session) { { 'authenticated' => true, 'external_id' => 'ur_abc' } }
  let(:env) do
    {
      'rack.session' => session,
      'SCRIPT_NAME' => '/api/colonel',
      'PATH_INFO' => '/sessions',
    }
  end

  before do
    allow(OT).to receive(:ld)
    allow(Onetime::Customer).to receive(:load_by_extid_or_email).with('ur_abc').and_return(cust)
    # OrganizationLoader reaches for real models otherwise; this strategy's org
    # context is not what this file is about.
    allow(strategy).to receive(:load_organization_context).and_return(nil)
  end

  context 'when the admin session bound refuses the request' do
    before do
      allow(strategy).to receive(:admin_session_expiry_reason).and_return(:absolute)
    end

    it 'fails with the [ADMIN_SESSION_EXPIRED] marker and the reason' do
      result = strategy.authenticate(env, 'authenticated')

      expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
      expect(result.failure_reason)
        .to eq('[ADMIN_SESSION_EXPIRED] Admin session absolute timeout exceeded; sign in again')
    end

    it 'stamps the env flag so a REFUSED request is not counted as activity' do
      strategy.authenticate(env, 'authenticated')

      expect(env[lifetime::EXPIRED_ENV_KEY]).to eq('absolute')
    end

    # The bound runs BEFORE additional_checks, which is where role/permission
    # checks live: an expired admin session must not reach them.
    it 'never reaches additional_checks' do
      strategy.authenticate(env, 'authenticated')

      expect(strategy.additional_checks_ran).to be_nil
    end
  end

  context 'when the credential watermark already rejects the session' do
    # AFTER the watermark: a session that predates a password change is stale for
    # every surface, and that is the more fundamental refusal. The admin bound
    # must not run at all, so it cannot mask it with a different message.
    it 'reports the stale-credential failure and never consults the bound' do
      allow(strategy).to receive(:session_predates_credential_change?).and_return(true)
      expect(strategy).not_to receive(:admin_session_expiry_reason)

      result = strategy.authenticate(env, 'authenticated')

      expect(result.failure_reason).to match(/SESSION_STALE_CREDENTIALS/)
      expect(env).not_to have_key(lifetime::EXPIRED_ENV_KEY)
    end
  end

  context 'when the bound allows the request' do
    it 'authenticates, runs additional_checks and leaves no env flag' do
      allow(strategy).to receive(:admin_session_expiry_reason).and_return(nil)

      result = strategy.authenticate(env, 'authenticated')

      expect(result).to be_a(Otto::Security::Authentication::StrategyResult)
      expect(strategy.additional_checks_ran).to be true
      expect(env).not_to have_key(lifetime::EXPIRED_ENV_KEY)
    end
  end
end
