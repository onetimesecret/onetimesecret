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

  # A session established on the canonical surface, marker matching the env
  # below (#4409). Surface-specific coverage is in the last context of this
  # file; here the marker is set so the surface check passes and the tests
  # focused on other predicates reach them.
  let(:session) do
    {
      'authenticated'              => true,
      'external_id'                => 'ur_abc',
      Onetime::SessionSurface::KEY => { 'kind' => 'canonical' },
    }
  end
  let(:env) do
    {
      'rack.session'            => session,
      'SCRIPT_NAME'             => '/api/colonel',
      'PATH_INFO'               => '/sessions',
      'onetime.domain_strategy' => :canonical,
    }
  end

  before do
    allow(OT).to receive(:ld)
    allow(Onetime::Customer).to receive(:find_by_extid).with('ur_abc').and_return(cust)
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

    # #4462: Otto renders the 401 from the failure string alone, so the typed
    # reason is handed to Onetime::Middleware::SessionFailureCode through env.
    it 'hands the typed reason to the failure-code middleware' do
      strategy.authenticate(env, 'authenticated')

      expect(env[Onetime::SessionFailureCode::ENV_KEY]).to eq(:admin_session_expired)
    end

    # The bound runs BEFORE additional_checks, which is where role/permission
    # checks live: an expired admin session must not reach them.
    it 'never reaches additional_checks' do
      strategy.authenticate(env, 'authenticated')

      expect(strategy.additional_checks_ran).to be_nil
    end

    # The bound also runs BEFORE the active-session gate: the gate refreshes
    # the active-session row's last_use, and a request this bound refuses is
    # not activity — on the sidecar (EXPIRED_ENV_KEY) or on the row.
    it 'never consults the active-session gate, so the refused request does not touch the row' do
      allow(Onetime::ActiveSessionGate).to receive(:verdict)

      strategy.authenticate(env, 'authenticated')

      expect(Onetime::ActiveSessionGate).not_to have_received(:verdict)
    end
  end

  context 'when the gate reports the active-session row has been revoked' do
    # Full-mode revocation (Onetime::ActiveSessionGate): AFTER the watermark
    # and the admin bound (both refuse without an authdb round trip), BEFORE
    # additional_checks. The gate is consulted with the env so its verdict is
    # memoized for the rest of the request.
    before do
      allow(strategy).to receive(:admin_session_expiry_reason).and_return(nil)
      allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:revoked)
    end

    it 'fails with the [SESSION_REVOKED] marker' do
      result = strategy.authenticate(env, 'authenticated')

      expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
      expect(result.failure_reason).to match(/\A\[SESSION_REVOKED\]/)
    end

    it 'consults the gate with the Rack env (shared per-request memo)' do
      strategy.authenticate(env, 'authenticated')

      expect(Onetime::ActiveSessionGate).to have_received(:verdict).with(session, env: env)
    end

    # Fail closed, but under its own marker: an outage must read as an outage
    # in the logs, never as a revocation the operator did not perform.
    it 'refuses a Rack session whose active-session row cannot be checked, with the [SESSION_UNVERIFIED] marker' do
      allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:unavailable)

      result = strategy.authenticate(env, 'authenticated')

      expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
      expect(result.failure_reason).to match(/\A\[SESSION_UNVERIFIED\]/)
    end

    it 'runs after the admin bound and never reaches additional_checks' do
      strategy.authenticate(env, 'authenticated')

      expect(strategy).to have_received(:admin_session_expiry_reason)
      expect(strategy.additional_checks_ran).to be_nil
    end
  end

  context 'when the credential watermark already rejects the session' do
    # AFTER the watermark: a session that predates a password change is stale for
    # every surface, and that is the more fundamental refusal. The admin bound
    # must not run at all, so it cannot mask it with a different message.
    it 'reports the stale-credential failure and never consults the gate or the bound' do
      allow(cust).to receive(:last_password_update).and_return(Familia.now.to_i)
      expect(Onetime::ActiveSessionGate).not_to receive(:verdict)
      expect(strategy).not_to receive(:admin_session_expiry_reason)

      result = strategy.authenticate(env, 'authenticated')

      expect(result.failure_reason).to include('SESSION_STALE_CREDENTIALS')
      expect(env).not_to have_key(lifetime::EXPIRED_ENV_KEY)
      expect(env[Onetime::SessionFailureCode::ENV_KEY]).to eq(:stale_credentials)
    end
  end

  context 'when the bound allows the request' do
    it 'authenticates, runs additional_checks and leaves no env flag' do
      allow(strategy).to receive(:admin_session_expiry_reason).and_return(nil)

      result = strategy.authenticate(env, 'authenticated')

      expect(result).to be_a(Otto::Security::Authentication::StrategyResult)
      expect(strategy.additional_checks_ran).to be true
      expect(env).not_to have_key(lifetime::EXPIRED_ENV_KEY)
      expect(env).not_to have_key(Onetime::SessionFailureCode::ENV_KEY)
    end
  end

  # #4455/#4463: `failure_for` is non-terminal, so on chained-strategy
  # routes such as `sessionauth,basicauth` (e.g. /api/account/) a rejected
  # verdict still lets Otto try the next strategy. Emitting "Session refused"
  # for a request that never presented a session identity is misleading — the
  # session had nothing to say. Log a refusal only when a credentialed
  # session was actually inspected and rejected.
  context 'refusal logging gate' do
    let(:logger) { double('auth_logger', debug: nil, info: nil, warn: nil, error: nil) }

    before { allow(Onetime).to receive(:auth_logger).and_return(logger) }

    it 'does not log when no session cookie is present (session_missing)' do
      env['rack.session'] = nil

      strategy.authenticate(env, 'authenticated')

      expect(logger).not_to have_received(:info)
      expect(logger).not_to have_received(:debug)
      expect(logger).not_to have_received(:warn)
      expect(env[Onetime::SessionFailureCode::ENV_KEY]).to eq(:session_missing)
    end

    it 'does not log when the session has no authenticated flag (not_authenticated)' do
      env['rack.session'] = { Onetime::SessionSurface::KEY => { 'kind' => 'canonical' } }

      strategy.authenticate(env, 'authenticated')

      expect(logger).not_to have_received(:info)
      expect(logger).not_to have_received(:debug)
      expect(logger).not_to have_received(:warn)
      expect(env[Onetime::SessionFailureCode::ENV_KEY]).to eq(:not_authenticated)
    end

    it 'does not log when the session is authenticated but carries no external_id (identity_missing)' do
      env['rack.session'] = {
        'authenticated'              => true,
        Onetime::SessionSurface::KEY => { 'kind' => 'canonical' },
      }

      strategy.authenticate(env, 'authenticated')

      expect(logger).not_to have_received(:info)
      expect(logger).not_to have_received(:debug)
      expect(logger).not_to have_received(:warn)
      expect(env[Onetime::SessionFailureCode::ENV_KEY]).to eq(:identity_missing)
    end

    it 'logs when a credentialed session is refused on a surface mismatch' do
      env['onetime.domain_strategy']  = :custom
      env['onetime.display_domain']   = 'secrets.acme.com'
      env['onetime.custom_domain_id'] = 'tenant-a'

      strategy.authenticate(env, 'authenticated')

      expect(logger).to have_received(:info).with('Session refused', hash_including(code: 'surface_mismatch'))
      expect(env[Onetime::SessionFailureCode::ENV_KEY]).to eq(:surface_mismatch)
    end

    it 'logs when the active-session gate revokes a credentialed session' do
      allow(strategy).to receive(:admin_session_expiry_reason).and_return(nil)
      allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:revoked)

      strategy.authenticate(env, 'authenticated')

      expect(logger).to have_received(:info).with('Session refused', hash_including(code: 'active_session_revoked'))
      expect(env[Onetime::SessionFailureCode::ENV_KEY]).to eq(:active_session_revoked)
    end

    it 'logs when a credentialed session is refused for stale credentials' do
      # The gate does not distinguish routes: a non-routine reason emits
      # regardless of whether a follow-on strategy is registered, because
      # the credentialed session was inspected and rejected.
      allow(cust).to receive(:last_password_update).and_return(Familia.now.to_i)

      strategy.authenticate(env, 'authenticated')

      expect(logger).to have_received(:info).with('Session refused', hash_including(code: 'stale_credentials'))
      expect(env[Onetime::SessionFailureCode::ENV_KEY]).to eq(:stale_credentials)
    end
  end

  # Surface-bound session enforcement (#4409). The check runs BEFORE the
  # customer load, the admin bound and the active-session gate: a mismatched
  # or missing marker refuses without an authdb round trip and without
  # touching Redis, so a cross-surface cookie cannot even be counted as
  # activity. Regression cases mirror the epic's acceptance criteria.
  context 'surface-bound session enforcement' do
    let(:session) do
      {
        'authenticated'              => true,
        'external_id'                => 'ur_abc',
        Onetime::SessionSurface::KEY => stored_surface,
      }
    end
    let(:env) do
      {
        'rack.session'             => session,
        'SCRIPT_NAME'              => '/api/colonel',
        'PATH_INFO'                => '/sessions',
        'onetime.domain_strategy'  => request_strategy,
        'onetime.display_domain'   => request_host,
        'onetime.custom_domain_id' => request_custom_id,
      }
    end
    let(:request_host)      { nil }
    let(:request_custom_id) { nil }

    shared_examples 'refuses with SESSION_SURFACE_MISMATCH' do
      it 'refuses before the customer load and the authdb gate' do
        expect(Onetime::Customer).not_to receive(:find_by_extid)
        expect(Onetime::ActiveSessionGate).not_to receive(:verdict)

        result = strategy.authenticate(env, 'authenticated')

        expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
        expect(result.failure_reason).to match(/\A\[SESSION_SURFACE_MISMATCH\]/)
      end
    end

    context 'platform session on tenant surface' do
      let(:stored_surface)    { { 'kind' => 'canonical' } }
      let(:request_strategy)  { :custom }
      let(:request_host)      { 'secrets.acme.com' }
      let(:request_custom_id) { 'tenant-a' }

      include_examples 'refuses with SESSION_SURFACE_MISMATCH'
    end

    context 'tenant session on platform surface' do
      let(:stored_surface)   { { 'kind' => 'custom', 'id' => 'tenant-a' } }
      let(:request_strategy) { :canonical }

      include_examples 'refuses with SESSION_SURFACE_MISMATCH'
    end

    context 'tenant A session on tenant B surface' do
      let(:stored_surface)    { { 'kind' => 'custom', 'id' => 'tenant-a' } }
      let(:request_strategy)  { :custom }
      let(:request_host)      { 'secrets.b.example' }
      let(:request_custom_id) { 'tenant-b' }

      include_examples 'refuses with SESSION_SURFACE_MISMATCH'
    end

    context 'canonical session on canonical subdomain' do
      let(:stored_surface)   { { 'kind' => 'canonical' } }
      let(:request_strategy) { :subdomain }
      let(:request_host)     { 'eu.example.com' }

      include_examples 'refuses with SESSION_SURFACE_MISMATCH'
    end

    context 'legacy session with no marker on canonical' do
      let(:session) { { 'authenticated' => true, 'external_id' => 'ur_abc' } }
      let(:env) do
        {
          'rack.session'            => session,
          'SCRIPT_NAME'             => '/api/colonel',
          'PATH_INFO'               => '/sessions',
          'onetime.domain_strategy' => :canonical,
        }
      end

      it 'refuses (missing marker is treated as mismatch; user re-authenticates)' do
        expect(Onetime::Customer).not_to receive(:find_by_extid)

        result = strategy.authenticate(env, 'authenticated')

        expect(result).to be_a(Otto::Security::Authentication::AuthFailure)
        expect(result.failure_reason).to match(/\A\[SESSION_SURFACE_MISMATCH\]/)
      end
    end
  end
end
