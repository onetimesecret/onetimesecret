# apps/web/auth/spec/config/hooks/login_colonel_signin_failure_spec.rb
#
# frozen_string_literal: true

# Unit tests for the colonel.signin_failed audit event emitted by the Rodauth
# after_login_failure hook (the FULL-auth-mode failed-sign-in site, #4339).
#
# A successful colonel.signin has been audited at both auth modes' session
# sites; a FAILED one recorded nothing at all. A brute-force against an admin
# account — the highest-signal security event the trail could hold — was
# therefore invisible. The old rationale (the operator trail is count-capped
# with no TTL, so an unauthenticated writer is a log-eviction primitive) still
# holds for `events`, which is why this writes to `security_events` instead.
#
# WHY THE HOOK IS DRIVEN BY HAND. A full Rodauth login-failure round trip needs
# the auth SQL database, which the fast lane has no Postgres for. So the hook
# BLOCK is captured off a stub `auth` and instance_exec'd against a stub Rodauth
# instance — the same "configure a double, assert what it registers" shape the
# neighbouring config specs use (config/features/omniauth_providers_spec.rb).
# What that pins is exactly what this change owns: the guard, the verb, the
# obscured target and the fail-open posture. The peer for the SUCCESS half is
# ../../operations/sync_session_colonel_signin_spec.rb, which drives its
# private method directly for the same reason.
#
# OUT OF SCOPE: the Rodauth SQL audit log (account_authentication_audit_logs)
# is a separate stream with its own writer and is untouched by #4339.
#
# Run: pnpm run test:rspec apps/web/auth/spec/config/hooks/login_colonel_signin_failure_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'onetime/colonel_signin_failure'
require 'auth/lib/logging'

# Define the Auth::Config namespace so the hook file can load without a full
# auth-app boot. Auth::Config MUST be a Rodauth::Auth subclass here, never a
# plain module/class: if this file is ever loaded in a process that also boots
# the real app, the application registry reopens `class Config < Rodauth::Auth`,
# and a wrongly-typed constant makes that reopen raise a TypeError that marks
# boot permanently not-ready for every later spec in the process. Same shim as
# ../features/omniauth_providers_spec.rb.
require 'rodauth'
module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Hooks, Module.new) unless Auth::Config.const_defined?(:Hooks, false)

require 'auth/config/hooks/login'

RSpec.describe Auth::Config::Hooks::Login do
  let(:hooks) { {} }

  # Stands in for the Rodauth class Login.configure registers hooks on. Hooks do
  # not chain in Rodauth (each call overwrites), so capturing the last block per
  # name is faithful.
  let(:auth) do
    double('auth').tap do |a|
      %i[before_login_attempt after_login after_login_failure].each do |hook|
        allow(a).to receive(hook) { |&blk| hooks[hook] = blk }
      end
    end
  end

  # Stands in for the Rodauth INSTANCE the hook body is instance_exec'd on.
  let(:rodauth) do
    double('Rodauth').tap do |r|
      allow(r).to receive(:param_or_nil).with('login').and_return(submitted_login)
      allow(r).to receive(:param_or_nil).with('email').and_return(nil)
      allow(r).to receive(:session).and_return({ auth_correlation_id: 'corr_1' })
      allow(r).to receive(:db).and_return({ accounts: double('accounts', count: 12) })
      allow(r).to receive(:request).and_return(double('Request', ip: '203.0.113.7'))
    end
  end

  let(:submitted_login) { 'colonel@example.com' }

  let(:colonel) do
    double('Customer', role: 'colonel', obscure_email: 'co***@e***.com')
  end

  let(:plain_customer) do
    double('Customer', role: 'customer', obscure_email: 'us***@e***.com')
  end

  def run_login_failure_hook
    rodauth.instance_exec(&hooks[:after_login_failure])
  end

  before do
    allow(Auth::Logging).to receive(:generate_correlation_id).and_return('corr_1')
    allow(Auth::Logging).to receive(:log_auth_event)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Onetime::ColonelAuditEvent).to receive(:record_security)
    allow(Onetime::Customer).to receive(:find_by_email).and_return(colonel)
    allow(OT).to receive(:le)

    described_class.configure(auth)
  end

  it 'registers an after_login_failure hook' do
    expect(hooks[:after_login_failure]).to be_a(Proc)
  end

  it 'records exactly one event, with the OBSCURED email as target' do
    run_login_failure_hook

    # actor is 'anonymous', not 'unknown': the caller is unauthenticated by
    # construction on this route, and nobody has proven they are this account,
    # so an extid would be the wrong identity as well as a leak. The payload
    # also ships to the external ColonelAudit sink at write time, so it must be
    # safe to leave the process.
    expect(Onetime::ColonelAuditEvent).to have_received(:record_security).once.with(
      actor: 'anonymous',
      verb: 'colonel.signin_failed',
      target: 'co***@e***.com',
      result: :failure,
      detail: { auth_mode: 'full', failure_reason: 'invalid_credentials' },
    )
  end

  it 'uses the single-sourced verb constant (both auth modes must agree)' do
    expect(Onetime::ColonelAuditEvent::VERB_COLONEL_SIGNIN_FAILED).to eq('colonel.signin_failed')
  end

  it 'never writes the operator trail (its budget is the whole point)' do
    run_login_failure_hook

    expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
  end

  it 'still writes the login_failure log line it has always written' do
    run_login_failure_hook

    expect(Auth::Logging).to have_received(:log_auth_event).with(
      :login_failure,
      hash_including(email: 'co***@e***.com', ip: '203.0.113.7'),
    )
  end

  it 'resolves the submitted login the way Rodauth normalizes it' do
    # The Customer email index is exact-match, so a differently-cased or
    # whitespace-padded submission must still reach the same account —
    # OT::Utils.normalize_email is the helper Rodauth's normalize_login uses.
    allow(rodauth).to receive(:param_or_nil).with('login').and_return('  Colonel@Example.COM ')

    run_login_failure_hook

    expect(Onetime::Customer).to have_received(:find_by_email).with('colonel@example.com')
  end

  context 'when the attempted account is not a colonel' do
    before { allow(Onetime::Customer).to receive(:find_by_email).and_return(plain_customer) }

    it 'records nothing (CONTRACT 4: not an admin account)' do
      run_login_failure_hook

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record_security)
    end
  end

  context 'when the attempted account does not exist' do
    before { allow(Onetime::Customer).to receive(:find_by_email).and_return(nil) }

    it 'records nothing, so arbitrary submitted addresses cannot mint events' do
      run_login_failure_hook

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record_security)
    end
  end

  context 'when no login was submitted at all' do
    let(:submitted_login) { nil }

    it 'records nothing and does not go looking' do
      run_login_failure_hook

      expect(Onetime::Customer).not_to have_received(:find_by_email)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record_security)
    end
  end

  context 'on the empty-auth-database diagnostic branch' do
    before do
      allow(rodauth).to receive(:db).and_return({ accounts: double('accounts', count: 0) })
    end

    it 'still records exactly one event (both branches are the same failure)' do
      run_login_failure_hook

      expect(Onetime::ColonelAuditEvent).to have_received(:record_security).once
      expect(Auth::Logging).to have_received(:log_auth_event).with(
        :login_failure_empty_database,
        hash_including(:diagnostic_hint),
      )
    end
  end

  it 'never fails the login response because the audit write blew up' do
    allow(Onetime::ColonelAuditEvent).to receive(:record_security).and_raise(StandardError, 'boom')

    expect { run_login_failure_hook }.not_to raise_error
    expect(OT).to have_received(:le).with('[colonel.signin_failed] audit record failed', hash_including(:exception))
  end

  it 'never fails the login response because the customer lookup blew up' do
    allow(Onetime::Customer).to receive(:find_by_email).and_raise(StandardError, 'valkey down')

    expect { run_login_failure_hook }.not_to raise_error
    expect(OT).to have_received(:le).with('[colonel.signin_failed] audit record failed', hash_including(:exception))
  end
end
