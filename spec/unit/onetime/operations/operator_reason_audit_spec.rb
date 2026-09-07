# spec/unit/onetime/operations/operator_reason_audit_spec.rb
#
# frozen_string_literal: true

# #4338 — the operator-supplied WHY on a destructive verb.
#
# The trail already recorded who did what to whom and how it went. It never
# recorded WHY, so "ur_colonel purged ur_alice" could not be told apart from a
# GDPR erasure, a mistake, or an insider clearing their tracks without leaving
# the system to find the ticket. Every destructive op now takes an OPTIONAL
# `reason:` and puts it in its audit `detail`.
#
# Two invariants, and the second matters as much as the first because this is
# the OPTIONAL half of the rollout:
#
#   1. GIVEN a reason, it lands in `detail[:reason]` — on the applied event, and
#      also on the no-change and preview events, since an attempted-but-no-op
#      action and a reconnaissance preview each have a why too.
#
#   2. WITHOUT one, the detail hash is BYTE-FOR-BYTE its pre-#4338 self. No
#      `reason: nil` key. A blank/whitespace reason is treated as absent for the
#      same reason — an empty string in the trail reads as "they gave a reason"
#      when they did not.
#
# Message expectations, not store reads: `record` swallows its own errors, so a
# store read could pass or fail for reasons unrelated to the mechanism (the
# failure_audit_spec.rb / preview_and_no_change_audit_spec.rb convention).
# Destructive verbs also pass `fail_closed: true` (#4333), so the expectations
# carry it.
#
# Run: pnpm run test:rspec spec/unit/onetime/operations/operator_reason_audit_spec.rb

require 'spec_helper'
require 'onetime/audit_reason'
require 'onetime/models/colonel_audit_event'
require 'onetime/operations/dlq/purge'
require 'onetime/operations/memberships/remove'
require 'onetime/operations/memberships/set_role'
require 'onetime/operations/sessions/delete_session'
require 'auth/operations/customers/purge'
require 'auth/operations/customers/set_role'
require 'auth/operations/customers/set_suspension'

RSpec.describe 'operator-supplied reason on destructive verbs (#4338)' do
  let(:actor)  { 'ur_colonel_public' } # PUBLIC identity (extid/email)
  let(:reason) { 'GDPR erasure request #4412' }

  before do
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Onetime::ColonelAuditEvent).to receive(:record_access)
  end

  # ---------------------------------------------------------------------------
  # The shared rules, pinned once on the module that owns them
  # ---------------------------------------------------------------------------
  describe Onetime::AuditReason do
    # A tiny host so the module's private helpers can be exercised directly —
    # they are the single source of both rules, and every op inherits them.
    let(:host) do
      Class.new do
        include Onetime::AuditReason
        def initialize(reason) = @reason = normalize_reason(reason)
        def reason = @reason
        def detail(hash = nil) = with_reason(hash)
      end
    end

    it 'strips surrounding whitespace' do
      expect(host.new("  spam \n ").reason).to eq('spam')
    end

    it 'treats blank, whitespace-only and nil as ABSENT' do
      expect(host.new('').reason).to be_nil
      expect(host.new("   \t ").reason).to be_nil
      expect(host.new(nil).reason).to be_nil
    end

    # One UNDER the audit model's per-value truncation, so a reason that passes
    # here is never silently clipped on the way into the trail.
    it 'bounds the reason below ColonelAuditEvent::MAX_DETAIL_VALUE_LENGTH' do
      expect(described_class::MAX_LENGTH)
        .to be < Onetime::ColonelAuditEvent::MAX_DETAIL_VALUE_LENGTH

      trimmed = host.new('x' * 400).reason
      expect(trimmed.length).to eq(described_class::MAX_LENGTH)
    end

    it 'is NOT matched by the sensitive-key redaction pattern' do
      # If it were, every reason would be stored as [REDACTED] and the feature
      # would record nothing.
      expect('reason').not_to match(Onetime::ColonelAuditEvent::SENSITIVE_KEY_PATTERN)
    end

    it 'leaves the detail hash IDENTICAL when there is no reason' do
      original = { email: 'a***@e***.com' }
      expect(host.new(nil).detail(original)).to eq(original)
      expect(host.new('  ').detail(original)).to eq(original)
    end

    it 'leaves a nil detail nil when there is no reason' do
      expect(host.new(nil).detail).to be_nil
    end

    it 'merges the reason without disturbing the incumbent keys' do
      expect(host.new('spam').detail(email: 'a***@e***.com'))
        .to eq({ email: 'a***@e***.com', reason: 'spam' })
    end
  end

  # ---------------------------------------------------------------------------
  # Applied destructive events
  # ---------------------------------------------------------------------------
  describe Auth::Operations::Customers::Purge do
    let(:customer) do
      double('Customer', extid: 'ur_p', custid: 'cust_p', obscure_email: 'p***@e***.com')
    end

    before do
      deleter = instance_double(Auth::Operations::DeleteCustomer, call: true)
      revoker = instance_double(Onetime::Operations::Sessions::RevokeAllForCustomer, call: nil)
      allow(Auth::Operations::DeleteCustomer).to receive(:new).and_return(deleter)
      allow(Onetime::Operations::Sessions::RevokeAllForCustomer).to receive(:new).and_return(revoker)
    end

    it 'records the reason in the purge detail' do
      described_class.new(customer: customer, actor: actor, reason: reason).call

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'customer.purge',
        target: 'ur_p',
        result: :success,
        detail: { email: 'p***@e***.com', reason: reason },
        fail_closed: true,
      )
    end

    # The pre-#4338 shape, unchanged. An op that is never given a reason must
    # look exactly as it did.
    it 'omits the key entirely when no reason is given' do
      described_class.new(customer: customer, actor: actor).call

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(detail: { email: 'p***@e***.com' }),
      )
    end

    it 'treats a whitespace-only reason as no reason' do
      described_class.new(customer: customer, actor: actor, reason: "  \n ").call

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(detail: { email: 'p***@e***.com' }),
      )
    end
  end

  describe Onetime::Operations::Sessions::Delete do
    # This op records NO detail at all without a reason, so it pins the
    # nil-detail edge of the rule rather than the merge.
    let(:dbclient) { double('Redis', del: 1) }

    before do
      allow(Onetime::Operations::Sessions::Store)
        .to receive(:find_key).and_return('session:abc')
      allow(Onetime::Operations::Sessions::Store).to receive(:extract_id).and_return('abc')
      allow(Onetime::SessionSidecar).to receive(:purge)
    end

    it 'records a detail carrying ONLY the reason when one is given' do
      described_class.new(
        session_id: 'abc', actor: actor, reason: 'stolen laptop', dbclient: dbclient,
      ).call

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'session.delete',
        # The non-reversible #4330 handle, never the raw sid — the sid IS the
        # bearer cookie and this event ships to the external sink.
        target: Onetime::SessionMetadata.handle_for('abc'),
        result: :success,
        detail: { reason: 'stolen laptop' },
        fail_closed: true,
      )
    end

    it 'records a nil detail — the model default — when no reason is given' do
      described_class.new(session_id: 'abc', actor: actor, dbclient: dbclient).call

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(detail: nil),
      )
    end
  end

  # ---------------------------------------------------------------------------
  # No-change attempts (#4337) — an attempted-but-no-op action has a why too
  # ---------------------------------------------------------------------------
  describe 'no-change attempts carry the reason' do
    describe Auth::Operations::Customers::SetRole do
      let(:customer) { double('Customer', extid: 'ur_x', role: 'colonel') }

      it 'records the reason on the no_change event' do
        result = described_class.new(
          customer: customer, role: 'colonel', actor: actor, reason: 'probing per ticket 99',
        ).call

        expect(result.status).to eq(:no_change)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          actor: actor,
          verb: 'customer.set_role',
          target: 'ur_x',
          result: :success,
          detail: {
            outcome: 'no_change',
            from: 'colonel',
            to: 'colonel',
            reason: 'probing per ticket 99',
          },
        )
      end

      it 'leaves the no_change detail unchanged without one' do
        described_class.new(customer: customer, role: 'colonel', actor: actor).call

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(detail: { outcome: 'no_change', from: 'colonel', to: 'colonel' }),
        )
      end
    end

    describe Auth::Operations::Customers::SetSuspension do
      let(:customer) { double('Customer', extid: 'ur_y', role: 'customer', suspended?: true) }

      it 'records the reason on the no_change event' do
        result = described_class.new(
          customer: customer, suspended: true, actor: actor, reason: 'already handled',
        ).call

        expect(result.status).to eq(:no_change)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          actor: actor,
          verb: 'customer.suspend',
          target: 'ur_y',
          result: :success,
          detail: { outcome: 'no_change', suspended: true, reason: 'already handled' },
        )
      end
    end

    describe Onetime::Operations::Dlq::Purge do
      let(:channel)    { double('Channel', close: true, open?: false) }
      let(:connection) { double('Connection', create_channel: channel) }

      it 'records the reason on a live purge of an already-empty queue' do
        allow(Onetime::Operations::Dlq::Store).to receive(:queue_handle)
          .and_return(double('Queue', message_count: 0))

        result = described_class.new(
          connection: connection, queue: 'dlq.email.message', actor: actor,
          dry_run: false, reason: 'clearing poison batch',
        ).call

        expect(result.status).to eq(:empty)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          actor: actor,
          verb: 'queue.dlq.purge',
          target: 'dlq.email.message',
          result: :success,
          detail: { outcome: 'no_change', purged: 0, reason: 'clearing poison batch' },
        )
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Dry-run previews (#4337) — reconnaissance on a destructive verb
  # ---------------------------------------------------------------------------
  describe Onetime::Operations::Dlq::Purge do
    let(:channel)    { double('Channel', close: true, open?: false) }
    let(:connection) { double('Connection', create_channel: channel) }

    before do
      allow(Onetime::Operations::Dlq::Store).to receive(:queue_handle)
        .and_return(double('Queue', message_count: 7, purge: true))
    end

    it 'carries the reason onto the preview observation' do
      described_class.new(
        connection: connection, queue: 'dlq.email.message', actor: actor,
        dry_run: true, reason: 'clearing poison batch',
      ).call

      expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
        actor: actor,
        verb: 'queue.dlq.purge',
        target: 'dlq.email.message',
        result: 'preview',
        detail: { dry_run: true, count: 7, reason: 'clearing poison batch' },
      )
      # The preview still writes nothing to the OPERATOR trail (#4337).
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end

    it 'carries the reason onto the applied purge' do
      described_class.new(
        connection: connection, queue: 'dlq.email.message', actor: actor,
        reason: 'clearing poison batch',
      ).call

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'queue.dlq.purge',
        target: 'dlq.email.message',
        result: :success,
        detail: { purged: 7, reason: 'clearing poison batch' },
        fail_closed: true,
      )
    end
  end

  # ---------------------------------------------------------------------------
  # The one place `reason` is NOT the operator's: membership refusals
  # ---------------------------------------------------------------------------
  describe 'membership refusals keep `reason` meaning the refusal STATUS' do
    let(:org)      { double('Org', extid: 'org_1', objid: 'o1') }
    let(:customer) { double('Customer', extid: 'ur_m', objid: 'c1') }

    # This detail's `reason` key shipped long before #4338 and names WHY THE
    # SYSTEM refused. One key cannot mean two things, and renaming a shipped
    # audit key to make room would break every reader filtering on it. A refusal
    # mutated nothing, so the system's answer is the fact worth keeping.
    it 'does not overwrite it with the operator reason on Remove' do
      allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer).and_return(nil)

      result = Onetime::Operations::Memberships::Remove.new(
        org: org, customer: customer, actor: actor, reason: 'offboarding',
      ).call

      expect(result.status).to eq(:not_found)
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'membership.remove',
        target: 'ur_m',
        result: :failure,
        detail: { reason: 'not_found', role: nil, org_id: 'org_1' },
      )
    end

    it 'does not overwrite it with the operator reason on SetRole' do
      result = Onetime::Operations::Memberships::SetRole.new(
        org: org, customer: customer, new_role: 'wizard', actor: actor, reason: 'offboarding',
      ).call

      expect(result.status).to eq(:invalid_role)
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(result: :failure, detail: hash_including(reason: 'invalid_role')),
      )
    end
  end
end
