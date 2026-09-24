# apps/web/auth/spec/operations/customers/impersonate_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::Impersonate — the START half.
#
# Covers: the session marker it writes, the single start audit event (written
# fail-closed, and rolled back when the write fails), the ADR-023
# missing-actor refusal, and the five precondition guards. The session is a
# plain Hash, so nothing here touches the datastore.
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
        # A live overlay with no start event is the unattributable privileged
        # action the audit pair exists to rule out, so the write is fail-closed.
        fail_closed: true,
      )
    end
  end

  # The start record is fail-closed (#4333), and — unlike the destructive
  # members of that family — this op can unwind: the only mutation is the
  # session key. A failed start write must leave NO live impersonation, NO
  # orphan stop event, and must surface as the raise (never :started).
  describe 'audit write failure' do
    let(:write_failure) do
      Onetime::AuditWriteFailure.new(verb: 'customer.impersonate.start', target: 'ur_target')
    end

    before do
      allow(Onetime::ColonelAuditEvent).to receive(:record)
        .with(hash_including(verb: 'customer.impersonate.start'))
        .and_raise(write_failure)
    end

    it 'propagates Onetime::AuditWriteFailure instead of returning :started' do
      expect { op.call }.to raise_error(Onetime::AuditWriteFailure, /customer\.impersonate\.start/)
    end

    # The SAME instance, not a re-wrapped one: the audit_failures wrapper tags
    # what it has recorded on the exception object, so a fresh raise would
    # defeat that.
    it 're-raises the original exception instance' do
      expect { op.call }.to raise_error { |raised| expect(raised).to equal(write_failure) }
    end

    it 'rolls the marker back so the session is not impersonating' do
      expect { op.call }.to raise_error(Onetime::AuditWriteFailure)

      expect(session[Onetime::SessionImpersonation::SESSION_KEY]).to be_nil
      expect(Onetime::SessionImpersonation.active(session)).to be_nil
      expect(Onetime::SessionImpersonation.context).to be_nil
    end

    # clear!, not stop!: a stop event for an impersonation that never took
    # effect (and has no start event) would be an orphan in the trail.
    it 'does not record a stop event for the impersonation that never started' do
      expect { op.call }.to raise_error(Onetime::AuditWriteFailure)

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
        .with(hash_including(verb: 'customer.impersonate.stop'))
    end

    # The audit_failures wrapper sees the SAME exception instance and records
    # it under audit.write_failure with the missing verb in the detail — not
    # as a failed impersonate, which would be a wrong claim about the outcome.
    it 'records the missing trail under audit.write_failure, not as a failed start' do
      expect { op.call }.to raise_error(Onetime::AuditWriteFailure)

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
        .with(hash_including(verb: 'customer.impersonate.start', result: :failure))
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: 'ur_operator',
        verb: 'audit.write_failure',
        target: 'ur_target',
        result: :failure,
        detail: hash_including(
          failed_verb: 'customer.impersonate.start',
          error: 'Onetime::AuditWriteFailure',
        ),
      )
    end

    it 'leaves the session free to start again once the write works' do
      expect { op.call }.to raise_error(Onetime::AuditWriteFailure)

      allow(Onetime::ColonelAuditEvent).to receive(:record)
        .with(hash_including(verb: 'customer.impersonate.start'))
        .and_return({})

      expect(op.call.status).to eq(:started)
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
