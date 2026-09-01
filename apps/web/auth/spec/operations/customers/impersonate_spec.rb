# apps/web/auth/spec/operations/customers/impersonate_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::Impersonate — the START half.
#
# Covers: the session marker it writes, the single start audit event, the
# ADR-023 missing-actor refusal, and the five precondition guards. The session
# is a plain Hash, so nothing here touches the datastore.
#
# Run: tests/lanes/run unit --only apps/web/auth/spec/operations/customers/impersonate_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'auth/operations/customers/impersonate'

RSpec.describe Auth::Operations::Customers::Impersonate do
  let(:now) { 1_756_700_000 }

  let(:customer) do
    double(
      'Customer',
      role: 'customer',
      extid: 'ur_target',
      email: 'alice@example.com',
      anonymous?: false,
      suspended?: false,
    )
  end

  let(:session) { { 'external_id' => 'ur_operator', 'role' => 'colonel' } }

  before do
    allow(Familia).to receive(:now).and_return(now)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Onetime::EntitlementPreview).to receive(:clear_session!)
  end

  def op(**overrides)
    described_class.new(
      **{ customer: customer, actor: 'ur_operator', reason: 'ticket #123', session: session }
        .merge(overrides),
    )
  end

  describe 'successful start' do
    subject(:result) { op.call }

    it 'returns :started with the non-secret correlation id and the expiry' do
      expect(result.status).to eq(:started)
      expect(result.impersonation_id).to match(/\Aimp_[0-9a-f]{16}\z/)
      expect(result.expires_at).to eq(now + Onetime::SessionImpersonation::TTL)
      expect(result.actor).to eq('ur_operator')
      expect(result.reason).to eq('ticket #123')
    end

    # There is no bearer token any more — the earlier design's grant is gone.
    it 'exposes no capability material' do
      expect(result.members).to contain_exactly(
        :status, :customer, :actor, :reason, :impersonation_id, :expires_at,
      )
    end

    it 'writes the overlay marker onto the session' do
      result

      marker = session[Onetime::SessionImpersonation::SESSION_KEY]
      expect(marker['target_extid']).to eq('ur_target')
      expect(marker['target_email']).to eq('alice@example.com')
      expect(marker['reason']).to eq('ticket #123')
    end

    # Overlay, not swap: the session still belongs to the operator.
    it 'leaves external_id pointing at the operator' do
      result

      expect(session['external_id']).to eq('ur_operator')
    end

    it 'ends any entitlement preview first' do
      result

      expect(Onetime::EntitlementPreview).to have_received(:clear_session!).with(session)
    end

    it 'records exactly one start event with the reason and correlation id' do
      result

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: 'ur_operator',
        verb: 'customer.impersonate.start',
        target: 'ur_target',
        result: :success,
        detail: {
          reason: 'ticket #123',
          impersonation_id: result.impersonation_id,
          expires_at: now + Onetime::SessionImpersonation::TTL,
        },
      )
    end
  end

  describe 'refusals' do
    def expect_refusal(error, **overrides)
      expect { op(**overrides).call }.to raise_error(error)

      expect(session).not_to have_key(Onetime::SessionImpersonation::SESSION_KEY)
      expect(Onetime::ColonelAuditEvent)
        .not_to have_received(:record).with(hash_including(result: :success))
    end

    it 'refuses an empty actor (ADR-023)' do
      expect_refusal(described_class::MissingActor, actor: '')
    end

    it 'refuses a nil actor' do
      expect_refusal(described_class::MissingActor, actor: nil)
    end

    it 'refuses a blank reason' do
      expect_refusal(described_class::MissingReason, reason: '   ')
    end

    it 'refuses a session it cannot write to' do
      expect_refusal(described_class::MissingSession, session: nil)
    end

    it 'refuses an anonymous target' do
      allow(customer).to receive(:anonymous?).and_return(true)
      expect_refusal(described_class::AnonymousTarget)
    end

    it 'refuses a colonel-role target' do
      allow(customer).to receive(:role).and_return('colonel')
      expect_refusal(described_class::PrivilegedTarget)
    end

    it 'refuses a suspended target' do
      allow(customer).to receive(:suspended?).and_return(true)
      expect_refusal(described_class::SuspendedTarget)
    end

    # Silently replacing the marker would leave the first impersonation with no
    # stop event — a hole in the trail, not just a UX wrinkle.
    it 'refuses to stack a second impersonation on the same session' do
      op.call

      expect { op.call }.to raise_error(described_class::AlreadyImpersonating)
    end
  end

  describe 'actor normalization' do
    it 'accepts an object carrying a public extid' do
      actor = double('Customer', extid: 'ur_operator', email: 'ops@example.com')

      expect(op(actor: actor).call.actor).to eq('ur_operator')
    end

    it 'falls back to email when there is no extid' do
      actor = double('Customer', extid: '', email: 'ops@example.com')

      expect(op(actor: actor).call.actor).to eq('ops@example.com')
    end
  end
end
