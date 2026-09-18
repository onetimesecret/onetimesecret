# apps/web/auth/spec/unit/router_customer_session_gate_spec.rb
#
# frozen_string_literal: true

# Unit coverage for two invariants in apps/web/auth/router.rb's route block:
#
#   1. The outage re-check that promotes :customer_unavailable to an
#      ActiveSessionGate detail runs ONLY for :customer_unavailable. Every
#      definitive rejection reason (account_suspended, stale_credentials,
#      admin_session_expired, customer_not_found, identity_missing,
#      awaiting_mfa) must survive an ActiveSessionGate stub returning
#      :unavailable — otherwise the fallback would overwrite the reason with
#      :active_session_unavailable and the caller would preserve the cookie.
#
#   2. env['onetime.customer_session_verdict'] is forgotten after r.rodauth
#      runs, in BOTH the :halt (Rodauth answered the route) and pass-through
#      paths. Rodauth mutates session['authenticated']/awaiting_mfa in-band,
#      so an unforget'd memo goes stale for any downstream reader that also
#      reads env[ENV_KEY] later in the request.
#
# The specs run against a MINI Roda app that reproduces the route-block
# fragments under test verbatim. The alternative — booting Auth::Router — is
# gated on Rodauth's one-shot configuration and requires the integration lane.
# Keep the mini-app fragments byte-identical to router.rb; if that block ever
# refactors, this spec must move with it (or be replaced by an integration
# spec) rather than silently pass against a stale copy.

require 'roda'
require 'rack/test'
require 'securerandom'

require_relative '../spec_helper'
require 'onetime/session/customer_session_evaluator'
require 'onetime/session/active_session_gate'

RSpec.describe 'Auth::Router customer-session gate' do
  include Rack::Test::Methods

  let(:env_key) { Onetime::CustomerSessionEvaluator::ENV_KEY }

  # A stub verdict object that mirrors the real Verdict's read interface. Real
  # Verdict.new refuses non-authenticated status with a principal/customer, so
  # a canned rejection is easier to describe this way.
  def stub_verdict(status:, reason:)
    Struct.new(:status, :reason).new(status, reason).tap do |v|
      def v.authenticated?
        status == :authenticated
      end
    end
  end

  # Mini app for finding #1: reproduces the outage re-check block from
  # apps/web/auth/router.rb (the "if !customer_session_verdict.authenticated?
  # && session['authenticated'] == true && auth_session_reason ==
  # :customer_unavailable" branch) and returns the reason it settled on so
  # the spec can assert.
  let(:outage_check_app) do
    Class.new(Roda) do
      plugin :sessions, secret: SecureRandom.hex(64)
      plugin :json
      plugin :halt

      route do |r|
        r.post 'seed' do
          session['authenticated'] = true if r.params['authenticated']
          { ok: true }
        end

        r.get 'gate' do
          customer_session_verdict = Onetime::CustomerSessionEvaluator.evaluate(session, env: env)
          auth_session_reason      = customer_session_verdict.reason

          # BYTE-IDENTICAL to router.rb (see the invariant comment there).
          if !customer_session_verdict.authenticated? &&
             session['authenticated'] == true &&
             auth_session_reason == :customer_unavailable
            case Onetime::ActiveSessionGate.verdict(session, env: env)
            when :revoked
              auth_session_reason = :active_session_revoked
            when :unavailable
              auth_session_reason = :active_session_unavailable
            end
          end

          { reason: auth_session_reason.to_s }
        end
      end
    end
  end

  describe 'outage re-check (finding #1)' do
    let(:app) { outage_check_app }

    before do
      # Establish session['authenticated']=true (the guard's precondition).
      post '/seed', authenticated: true
      expect(last_response.status).to eq(200)
    end

    # Every definitive rejection reason from REASONS other than
    # :customer_unavailable and the authenticated/anonymous branches. Each
    # must survive an ActiveSessionGate returning :unavailable — the previous
    # allowlist masked all of these behind :active_session_unavailable.
    [
      :account_suspended,
      :stale_credentials,
      :admin_session_expired,
      :customer_not_found,
      :identity_missing,
      :awaiting_mfa,
    ].each do |reason|
      it "preserves #{reason} instead of overwriting it with :active_session_unavailable" do
        rejection_status = reason == :awaiting_mfa ? :mfa_pending : :rejected
        allow(Onetime::CustomerSessionEvaluator).to receive(:evaluate)
          .and_return(stub_verdict(status: rejection_status, reason: reason))
        expect(Onetime::ActiveSessionGate).not_to receive(:verdict)

        get '/gate'

        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body)['reason']).to eq(reason.to_s)
      end
    end

    it 'runs the ActiveSessionGate re-check for :customer_unavailable and adopts :active_session_unavailable' do
      allow(Onetime::CustomerSessionEvaluator).to receive(:evaluate)
        .and_return(stub_verdict(status: :unavailable, reason: :customer_unavailable))
      allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:unavailable)

      get '/gate'

      expect(Onetime::ActiveSessionGate).to have_received(:verdict)
      expect(JSON.parse(last_response.body)['reason']).to eq('active_session_unavailable')
    end

    it 'promotes :customer_unavailable to :active_session_revoked when the gate answers :revoked' do
      allow(Onetime::CustomerSessionEvaluator).to receive(:evaluate)
        .and_return(stub_verdict(status: :unavailable, reason: :customer_unavailable))
      allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:revoked)

      get '/gate'

      expect(JSON.parse(last_response.body)['reason']).to eq('active_session_revoked')
    end
  end

  # Mini app for finding #8: reproduces the begin/ensure wrap around r.rodauth.
  # `r.rodauth` is stubbed by a lambda that mutates the session (as real Rodauth
  # would) and either returns normally or throws :halt (as Rodauth does when it
  # answers a route). The ensure clause must call
  # CustomerSessionEvaluator.forget(env) on both paths so the memo does not go
  # stale for a downstream reader.
  let(:memo_forget_app) do
    Class.new(Roda) do
      plugin :sessions, secret: SecureRandom.hex(64)
      plugin :json
      plugin :halt

      route do |r|
        r.get 'run' do
          env[Onetime::CustomerSessionEvaluator::ENV_KEY] = :stale_memo

          # BYTE-IDENTICAL to router.rb: begin/ensure with forget in ensure.
          # The stub uses env['test.rodauth'] as the injection point since a
          # mini-app has no real r.rodauth.
          begin
            env['test.rodauth'].call(session)
          ensure
            Onetime::CustomerSessionEvaluator.forget(env)
          end

          { reason: env[Onetime::CustomerSessionEvaluator::ENV_KEY].inspect }
        end
      end
    end
  end

  describe 'memo invalidation after r.rodauth (finding #8)' do
    let(:app) { memo_forget_app }

    it 'forgets env[ENV_KEY] after the r.rodauth pass-through path' do
      pass_through = ->(_session) { :ok }
      env_capture  = nil

      # Rack::Test env override so we can inject the stub and read env back.
      get '/run', {}, 'test.rodauth' => pass_through, 'rack.after_reply' => []
      env_capture = last_request.env

      expect(env_capture).not_to have_key(env_key),
        'the pass-through path must invalidate the memo'
    end

    it 'forgets env[ENV_KEY] when r.rodauth throws :halt (Rodauth answered the route)' do
      halting = lambda do |_session|
        # Mimic Rodauth's control-flow answer: throw :halt with a response.
        throw :halt, [200, { 'content-type' => 'application/json' }, ['{}']]
      end

      get '/run', {}, 'test.rodauth' => halting

      expect(last_request.env).not_to have_key(env_key),
        'the halt path is the only reliable invalidation point; ensure must fire'
    end
  end
end
