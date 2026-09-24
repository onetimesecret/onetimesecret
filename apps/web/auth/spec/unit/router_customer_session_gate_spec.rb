# apps/web/auth/spec/unit/router_customer_session_gate_spec.rb
#
# frozen_string_literal: true

# Unit coverage for two invariants in apps/web/auth/router.rb's route block:
#
#   1. The /auth-local re-check (Auth::SessionRecheck.reason_for) fills in the
#      surface and ActiveSessionGate checks ONLY for a Rodauth-logged-in Rack
#      session (account_id present) whose evaluator reason was returned before
#      those checks ran: :awaiting_mfa and :not_authenticated (surface, then
#      gate) and :customer_unavailable (gate only). Every definitive rejection
#      (account_suspended, stale_credentials, admin_session_expired,
#      customer_not_found, identity_missing) must survive an ActiveSessionGate
#      stub returning :unavailable — otherwise the fallback would overwrite
#      the reason with :active_session_unavailable and the caller would
#      preserve the cookie. A genuinely anonymous session (no account_id)
#      never reaches either check.
#
#   2. env['onetime.customer_session_verdict'] is forgotten after r.rodauth
#      runs, in BOTH the :halt (Rodauth answered the route) and pass-through
#      paths. Rodauth mutates session['authenticated']/awaiting_mfa in-band,
#      so an unforget'd memo goes stale for any downstream reader that also
#      reads env[ENV_KEY] later in the request.
#
# The specs run against a MINI Roda app. Booting Auth::Router is gated on
# Rodauth's one-shot configuration and requires the integration lane. For
# invariant 1 the mini app calls Auth::SessionRecheck.reason_for, the same
# module function the router calls, so there is no copied fragment to drift.
# For invariant 2 the begin/ensure fragment is still reproduced by hand; keep
# it identical to router.rb.

require 'roda'
require 'rack/test'
require 'securerandom'

require_relative '../spec_helper'
require 'onetime/session/customer_session_evaluator'
require 'onetime/session/active_session_gate'
require_relative '../../session_recheck'

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

  def stub_evaluator(status:, reason:)
    allow(Onetime::CustomerSessionEvaluator).to receive(:evaluate)
      .and_return(stub_verdict(status: status, reason: reason))
  end

  def settled_reason
    get '/gate'
    expect(last_response.status).to eq(200)
    JSON.parse(last_response.body)['reason']
  end

  # Mini app for invariant 1: evaluates, hands the verdict to the router's
  # re-check, and returns the reason it settled on so the spec can assert.
  let(:recheck_app) do
    Class.new(Roda) do
      plugin :sessions, secret: SecureRandom.hex(64)
      plugin :json
      plugin :halt

      route do |r|
        r.post 'seed' do
          session['authenticated'] = true if r.params['authenticated']
          session['account_id']    = Integer(r.params['account_id']) if r.params['account_id']
          { ok: true }
        end

        r.get 'gate' do
          customer_session_verdict = Onetime::CustomerSessionEvaluator.evaluate(session, env: env)
          auth_session_reason      = Auth::SessionRecheck.reason_for(customer_session_verdict, session, env)

          { reason: auth_session_reason.to_s }
        end
      end
    end
  end

  describe '/auth-local surface and active-session re-check' do
    let(:app) { recheck_app }

    context 'with a Rodauth-logged-in Rack session (account_id present)' do
      before do
        post '/seed', authenticated: true, account_id: 42
        expect(last_response.status).to eq(200)
        allow(Onetime::SessionSurface).to receive(:match_status).and_return(:match)
      end

      # Every definitive rejection reason from REASONS. Each must survive an
      # ActiveSessionGate that would answer :unavailable: the gate is never
      # consulted for them.
      [
        :account_suspended,
        :stale_credentials,
        :admin_session_expired,
        :customer_not_found,
        :identity_missing,
      ].each do |reason|
        it "preserves #{reason} instead of overwriting it with :active_session_unavailable" do
          stub_evaluator(status: :rejected, reason: reason)
          allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:unavailable)

          expect(settled_reason).to eq(reason.to_s)
          expect(Onetime::ActiveSessionGate).not_to have_received(:verdict)
          expect(Onetime::SessionSurface).not_to have_received(:match_status)
        end
      end

      it 'leaves an authenticated verdict alone without consulting the gate again' do
        stub_evaluator(status: :authenticated, reason: :authenticated)
        allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:revoked)

        expect(settled_reason).to eq('authenticated')
        expect(Onetime::ActiveSessionGate).not_to have_received(:verdict)
      end

      context 'when the evaluator answers :customer_unavailable' do
        before { stub_evaluator(status: :unavailable, reason: :customer_unavailable) }

        it 'runs the ActiveSessionGate re-check and adopts :active_session_unavailable' do
          allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:unavailable)

          expect(settled_reason).to eq('active_session_unavailable')
          expect(Onetime::ActiveSessionGate).to have_received(:verdict)
        end

        it 'promotes to :active_session_revoked when the gate answers :revoked' do
          allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:revoked)

          expect(settled_reason).to eq('active_session_revoked')
        end

        it 'does not repeat the surface check the evaluator already passed' do
          allow(Onetime::SessionSurface).to receive(:match_status).and_return(:mismatch)
          allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:active)

          expect(settled_reason).to eq('customer_unavailable')
          expect(Onetime::SessionSurface).not_to have_received(:match_status)
        end
      end

      # The two reasons the evaluator returns before its surface check. Both
      # describe a session Rodauth would authorize from account_id alone.
      {
        awaiting_mfa: :mfa_pending,
        not_authenticated: :anonymous,
      }.each do |reason, status|
        context "when the evaluator answers :#{reason}" do
          before { stub_evaluator(status: status, reason: reason) }

          it 'becomes :active_session_revoked when the gate answers :revoked' do
            allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:revoked)

            expect(settled_reason).to eq('active_session_revoked')
          end

          it 'becomes :active_session_unavailable when the gate answers :unavailable' do
            allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:unavailable)

            expect(settled_reason).to eq('active_session_unavailable')
          end

          it 'becomes :surface_mismatch on a surface mismatch, before the gate is consulted' do
            allow(Onetime::SessionSurface).to receive(:match_status).and_return(:mismatch)
            allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:active)

            expect(settled_reason).to eq('surface_mismatch')
            expect(Onetime::ActiveSessionGate).not_to have_received(:verdict)
          end

          context 'when the request surface cannot be read' do
            before { allow(Onetime::SessionSurface).to receive(:match_status).and_return(:unavailable) }

            it 'becomes :customer_unavailable, which keeps the session, when the gate answers :active' do
              allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:active)

              expect(settled_reason).to eq('customer_unavailable')
            end

            it 'still becomes :active_session_revoked when the gate answers :revoked' do
              allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:revoked)

              expect(settled_reason).to eq('active_session_revoked')
            end
          end

          [:active, :skipped].each do |gate_verdict|
            it "stands when the surface matches and the gate answers :#{gate_verdict}" do
              allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(gate_verdict)

              expect(settled_reason).to eq(reason.to_s)
              expect(Onetime::SessionSurface).to have_received(:match_status)
              expect(Onetime::ActiveSessionGate).to have_received(:verdict)
            end
          end
        end
      end
    end

    context 'with a genuinely anonymous Rack session (no account_id)' do
      before do
        allow(Onetime::SessionSurface).to receive(:match_status).and_return(:mismatch)
        allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:revoked)
      end

      it 'leaves :not_authenticated alone and consults neither check' do
        stub_evaluator(status: :anonymous, reason: :not_authenticated)

        expect(settled_reason).to eq('not_authenticated')
        expect(Onetime::SessionSurface).not_to have_received(:match_status)
        expect(Onetime::ActiveSessionGate).not_to have_received(:verdict)
      end

      it 'leaves :session_missing alone and consults neither check' do
        stub_evaluator(status: :anonymous, reason: :session_missing)

        expect(settled_reason).to eq('session_missing')
        expect(Onetime::ActiveSessionGate).not_to have_received(:verdict)
      end
    end
  end

  # Mini app for invariant 2: reproduces the begin/ensure wrap around r.rodauth.
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

  describe 'memo invalidation after r.rodauth (invariant 2)' do
    let(:app) { memo_forget_app }

    it 'forgets env[ENV_KEY] after the r.rodauth pass-through path' do
      pass_through = ->(_session) { :ok }

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
