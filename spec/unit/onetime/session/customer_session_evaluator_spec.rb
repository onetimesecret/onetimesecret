# frozen_string_literal: true

require 'spec_helper'
require 'onetime/session/customer_session_evaluator'

RSpec.describe Onetime::CustomerSessionEvaluator do
  # A session Hash that records which keys the evaluator reads, in order.
  let(:tracking_session_class) do
    Class.new(Hash) do
      attr_reader :events

      def initialize(values, events)
        @events = events
        super()
        merge!(values)
      end

      def [](key)
        events << key
        super
      end
    end
  end

  let(:events) { [] }
  let(:env) { { 'onetime.domain_strategy' => :canonical } }
  let(:session) do
    tracking_session_class.new(
      {
        'authenticated' => true,
        'authenticated_at' => 101,
        'external_id' => 'ur_principal',
        Onetime::SessionSurface::KEY => { 'kind' => 'canonical' },
      },
      events,
    )
  end
  let(:principal) do
    instance_double(
      Onetime::Customer,
      suspended?: false,
      last_password_update: 100,
    )
  end
  let(:effective_customer) { principal }

  before do
    allow(Onetime::SessionSurface).to receive(:matches_request?) do
      events << :surface
      true
    end
    allow(Onetime::Customer).to receive(:find_by_extid) do
      events << :customer_load
      principal
    end
    allow(principal).to receive(:suspended?) do
      events << :suspension
      false
    end
    allow(principal).to receive(:last_password_update) do
      events << :credential_watermark
      100
    end
    allow(Onetime::ActiveSessionGate).to receive(:verdict) do
      events << :active_session
      :active
    end
    allow(Onetime::SessionImpersonation).to receive(:resolve) do
      events << :impersonation
      [effective_customer, nil]
    end
  end

  it 'evaluates the policy in the established order, including the caller-owned admin boundary' do
    before_active = lambda do |_customer|
      events << :admin_boundary
      nil
    end

    verdict = described_class.evaluate(session, env: env, before_active: before_active)

    expect(verdict.status).to eq(:authenticated)
    expect(verdict.customer).to be(effective_customer)
    expect(events).to eq([
      'awaiting_mfa',
      'authenticated',
      'external_id',
      :surface,
      :customer_load,
      :suspension,
      :credential_watermark,
      'authenticated_at',
      :admin_boundary,
      :active_session,
      :impersonation,
    ])
  end

  it 'returns MFA-pending without loading or exposing an identity' do
    session['awaiting_mfa'] = true

    verdict = described_class.evaluate(session, env: env)

    expect(verdict.status).to eq(:mfa_pending)
    expect(verdict.reason).to eq(:awaiting_mfa)
    expect(verdict.principal).to be_nil
    expect(verdict.customer).to be_nil
    expect(Onetime::Customer).not_to have_received(:find_by_extid)
  end

  it 'returns unavailable without exposing an identity when active membership cannot be checked' do
    allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:unavailable)

    verdict = described_class.evaluate(session, env: env)

    expect(verdict.status).to eq(:unavailable)
    expect(verdict.reason).to eq(:active_session_unavailable)
    expect(verdict.principal).to be_nil
    expect(verdict.customer).to be_nil
    expect(Onetime::SessionImpersonation).not_to have_received(:resolve)
  end

  it 'returns unavailable without exposing an identity when customer resolution raises' do
    allow(Onetime::Customer).to receive(:find_by_extid)
      .and_raise(Redis::ConnectionError, 'customer store unavailable')

    verdict = described_class.evaluate(session, env: env)

    expect(verdict.status).to eq(:unavailable)
    expect(verdict.reason).to eq(:customer_unavailable)
    expect(verdict.principal).to be_nil
    expect(verdict.customer).to be_nil
    expect(Onetime::ActiveSessionGate).not_to have_received(:verdict)
    expect(Onetime::SessionImpersonation).not_to have_received(:resolve)
  end

  it 'returns unavailable when a loaded customer cannot be checked for suspension' do
    allow(principal).to receive(:suspended?).and_raise(Redis::ConnectionError, 'customer store unavailable')

    verdict = described_class.evaluate(session, env: env)

    expect(verdict.status).to eq(:unavailable)
    expect(verdict.reason).to eq(:customer_unavailable)
    expect(verdict.principal).to be_nil
    expect(verdict.customer).to be_nil
    expect(principal).not_to have_received(:last_password_update)
    expect(Onetime::ActiveSessionGate).not_to have_received(:verdict)
  end

  it 'returns unavailable when a loaded customer credential watermark cannot be checked' do
    allow(principal).to receive(:last_password_update).and_raise(Redis::ConnectionError, 'customer store unavailable')

    verdict = described_class.evaluate(session, env: env)

    expect(verdict.status).to eq(:unavailable)
    expect(verdict.reason).to eq(:customer_unavailable)
    expect(verdict.principal).to be_nil
    expect(verdict.customer).to be_nil
    expect(Onetime::ActiveSessionGate).not_to have_received(:verdict)
  end

  it 'does not broaden compatibility handling to surface predicate programmer errors' do
    allow(Onetime::SessionSurface).to receive(:matches_request?).and_raise(NoMethodError, 'surface bug')

    expect { described_class.evaluate(session, env: env) }
      .to raise_error(NoMethodError, 'surface bug')
  end

  it 'does not broaden compatibility handling to caller-owned boundary errors' do
    boundary = ->(_customer) { raise ArgumentError, 'boundary bug' }

    expect { described_class.evaluate(session, env: env, before_active: boundary) }
      .to raise_error(ArgumentError, 'boundary bug')
  end

  it 'keeps a missing customer as a definitive rejection' do
    allow(Onetime::Customer).to receive(:find_by_extid).and_return(nil)

    verdict = described_class.evaluate(session, env: env)

    expect(verdict.status).to eq(:rejected)
    expect(verdict.reason).to eq(:customer_not_found)
    expect(verdict.customer).to be_nil
  end

  it 'rejects a suspended principal before the credential, active-session, and impersonation checks' do
    allow(principal).to receive(:suspended?).and_return(true)

    verdict = described_class.evaluate(session, env: env)

    expect(verdict.status).to eq(:rejected)
    expect(verdict.reason).to eq(:account_suspended)
    expect(verdict.customer).to be_nil
    expect(principal).not_to have_received(:last_password_update)
    expect(Onetime::ActiveSessionGate).not_to have_received(:verdict)
    expect(Onetime::SessionImpersonation).not_to have_received(:resolve)
  end

  it 'keeps the legacy unstamped active-session exemption as skipped, not verified membership' do
    session.delete('active_session_id_hmac')
    allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:skipped)

    verdict = described_class.evaluate(session, env: env)

    expect(verdict.status).to eq(:authenticated)
    expect(Onetime::ActiveSessionGate).to have_received(:verdict).with(session, env: env)
  end

  it 'accepts an authenticated impersonation target only after the principal gates pass' do
    target = instance_double(Onetime::Customer)
    allow(Onetime::SessionImpersonation).to receive(:resolve).and_return([target, { 'id' => 'imp_1' }])

    verdict = described_class.evaluate(session, env: env)

    expect(verdict.status).to eq(:authenticated)
    expect(verdict.principal).to be(principal)
    expect(verdict.customer).to be(target)
    expect(verdict.impersonation).to eq({ 'id' => 'imp_1' })
  end

  describe 'the per-request memo and the caller-owned boundary' do
    let(:expired) do
      described_class::Verdict.new(status: :rejected, reason: :admin_session_expired, detail: :idle)
    end

    it 'applies before_active to an authenticated verdict cached by a caller without one' do
      expect(described_class.evaluate(session, env: env).status).to eq(:authenticated)

      seen    = []
      verdict = described_class.evaluate(
        session,
        env: env,
        before_active: ->(cust) do
          seen << cust
          expired
        end,
      )

      expect(seen).to eq([principal])
      expect(verdict).to be(expired)
      expect(described_class.evaluate(session, env: env)).to be(expired)
      expect(Onetime::Customer).to have_received(:find_by_extid).once
    end

    it 'returns the cached authenticated verdict when the boundary passes' do
      cached = described_class.evaluate(session, env: env)

      verdict = described_class.evaluate(session, env: env, before_active: ->(_cust) {})

      expect(verdict).to be(cached)
    end

    it 'does not run the boundary against a cached refusal' do
      allow(Onetime::ActiveSessionGate).to receive(:verdict).and_return(:revoked)
      cached   = described_class.evaluate(session, env: env)
      boundary = ->(_cust) { raise 'boundary must not run' }

      expect(described_class.evaluate(session, env: env, before_active: boundary)).to be(cached)
    end
  end

  it 'refuses an authenticated session as a surface mismatch when there is no Rack env' do
    allow(Onetime::SessionSurface).to receive(:matches_request?).and_call_original

    verdict = described_class.evaluate(session, env: nil)

    expect(verdict.status).to eq(:rejected)
    expect(verdict.reason).to eq(:surface_mismatch)
    expect(Onetime::Customer).not_to have_received(:find_by_extid)
  end

  describe described_class::Verdict do
    it 'refuses an authenticated verdict without a principal and a customer' do
      customer = instance_double(Onetime::Customer)

      expect { described_class.new(status: :authenticated, reason: :authenticated) }
        .to raise_error(ArgumentError, /requires a principal and a customer/)
      expect { described_class.new(status: :authenticated, reason: :authenticated, customer: customer) }
        .to raise_error(ArgumentError, /requires a principal and a customer/)
      expect { described_class.new(status: :authenticated, reason: :authenticated, principal: customer) }
        .to raise_error(ArgumentError, /requires a principal and a customer/)
    end
  end
end
