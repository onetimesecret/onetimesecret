# spec/unit/onetime/operations/preview_and_no_change_audit_spec.rb
#
# frozen_string_literal: true

# The two halves of #4337, which sit on OPPOSITE trails on purpose.
#
#   DRY-RUN PREVIEWS mutate nothing, so they never touch the operator trail —
#   but a preview enumerates exactly what a destructive run would touch, and
#   several of these ops default to dry_run=true, so the reconnaissance is
#   recorded as an OBSERVATION (`record_access`, `result: 'preview'`).
#
#   NO-CHANGE ATTEMPTS mutate nothing either, but they are deliberate mutation
#   ATTEMPTS — an operator reached for the suspend button, or for `colonel`, on
#   a named account. Those go on the OPERATOR trail under the op's normal verb
#   with `detail: { outcome: 'no_change' }`, because "someone tried" is the
#   fact a reviewer needs. Not fail_closed: nothing destructive happened.
#
# Message expectations, not store reads: both write paths swallow their own
# errors, so a store read could pass or fail for reasons unrelated to the
# mechanism (the failure_audit_spec.rb convention).
#
# Run: pnpm run test:rspec spec/unit/onetime/operations/preview_and_no_change_audit_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'onetime/operations/dlq/purge'
require 'onetime/operations/dlq/replay'
require 'onetime/operations/email/send_test'
require 'onetime/operations/memberships/add'
require 'onetime/operations/org/entitlement_override'
require 'auth/operations/customers/set_plan'
require 'auth/operations/customers/set_role'
require 'auth/operations/customers/set_suspension'

RSpec.describe 'preview and no-change auditing' do
  let(:actor) { 'ur_colonel_public' } # PUBLIC identity (extid/email)

  before do
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Onetime::ColonelAuditEvent).to receive(:record_access)
  end

  # ---------------------------------------------------------------------------
  # Dry-run previews -> the OBSERVATION trail
  # ---------------------------------------------------------------------------
  describe 'dry-run previews' do
    describe Onetime::Operations::Dlq::Purge do
      let(:channel) { double('Channel', close: true, open?: false) }
      let(:connection) { double('Connection', create_channel: channel) }

      before do
        allow(Onetime::Operations::Dlq::Store).to receive(:queue_handle)
          .and_return(double('Queue', message_count: 42))
      end

      def preview
        described_class.new(
          connection: connection, queue: 'dlq.email.message', actor: actor, dry_run: true,
        ).call
      end

      it 'records ONE preview observation carrying the count it measured' do
        result = preview

        expect(result.status).to eq(:dry_run)
        expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
          actor: actor,
          verb: described_class::AUDIT_VERB,
          target: 'dlq.email.message',
          result: 'preview',
          detail: { dry_run: true, count: 42 },
        )
      end

      # The half that protects the mutation trail: a preview of a destructive
      # verb must never look like the verb.
      it 'writes NOTHING to the operator trail' do
        preview

        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      end

      # Same verb and target as the applied event, so a preview and the purge
      # that followed it read as one sequence when filtered by verb.
      it 'uses the same verb and target the applied purge records' do
        allow(Onetime::Operations::Dlq::Store).to receive(:queue_handle)
          .and_return(double('Queue', message_count: 3, purge: true))

        described_class.new(
          connection: connection, queue: 'dlq.email.message', actor: actor, dry_run: false,
        ).call

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(verb: described_class::AUDIT_VERB, target: 'dlq.email.message'),
        )
      end
    end

    describe Onetime::Operations::Dlq::Replay do
      let(:channel) { double('Channel', close: true, open?: false) }
      let(:connection) { double('Connection', create_channel: channel) }

      it 'records what a replay WOULD re-fire, never message contents' do
        allow(Onetime::Operations::Dlq::Store).to receive(:queue_handle)
          .and_return(double('Queue', message_count: 10))

        described_class.new(
          connection: connection, queue: 'dlq.webhooks.payload', actor: actor,
          count: 4, dry_run: true,
        ).call

        expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
          actor: actor,
          verb: described_class::AUDIT_VERB,
          target: 'dlq.webhooks.payload',
          result: 'preview',
          detail: { dry_run: true, would_replay: 4, available: 10 },
        )
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      end
    end

    describe Onetime::Operations::Email::SendTest do
      it 'records the preview without dispatching anything' do
        diagnostic = double('Diagnostic', provider: 'ses')
        allow(described_class).to receive(:build).and_return(diagnostic)
        expect(Onetime::Mail::Mailer).not_to receive(:delivery_backend)

        result = described_class.new(to: 'ops@example.com', actor: actor, dry_run: true).call

        expect(result.status).to eq(:dry_run)
        expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
          actor: actor,
          verb: described_class::AUDIT_VERB,
          target: 'ops@example.com',
          result: 'preview',
          detail: { dry_run: true, provider: 'ses', enqueue: false },
        )
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # No-change attempts -> the OPERATOR trail
  # ---------------------------------------------------------------------------
  describe 'no-change attempts' do
    describe Auth::Operations::Customers::SetRole do
      let(:customer) { double('Customer', extid: 'ur_target_public', role: 'colonel') }

      it 'records the attempt under the normal verb, marked outcome: no_change' do
        result = described_class.new(customer: customer, role: 'colonel', actor: actor).call

        expect(result.status).to eq(:no_change)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          actor: actor,
          verb: described_class::AUDIT_VERB,
          target: 'ur_target_public',
          result: :success,
          detail: { outcome: 'no_change', from: 'colonel', to: 'colonel' },
        )
      end

      # No privilege moved, so there is no untraceable grant for a hard failure
      # to surface — and turning an idempotent no-op into a 500 would be a
      # regression.
      it 'is NOT fail-closed, unlike the applied role change' do
        described_class.new(customer: customer, role: 'colonel', actor: actor).call

        expect(Onetime::ColonelAuditEvent).to have_received(:record).with(hash_excluding(:fail_closed))
      end

      # A no-change mutated nothing but is not an observation: it is an
      # attempted mutation, and the operator trail is where attempts live.
      it 'does NOT go to the observation trail' do
        described_class.new(customer: customer, role: 'colonel', actor: actor).call

        expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access)
      end
    end

    describe Auth::Operations::Customers::SetPlan do
      let(:customer) { double('Customer', extid: 'ur_target_public', planid: 'identity_plus_v1') }

      it 'records a re-application of the current plan' do
        result = described_class.new(customer: customer, planid: 'identity_plus_v1', actor: actor).call

        expect(result.status).to eq(:no_change)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(
            verb: described_class::AUDIT_VERB,
            target: 'ur_target_public',
            detail: { outcome: 'no_change', from: 'identity_plus_v1', to: 'identity_plus_v1' },
          ),
        )
      end
    end

    describe Auth::Operations::Customers::SetSuspension do
      let(:customer) { double('Customer', extid: 'ur_target_public', role: 'customer', suspended?: true) }

      it 'records a re-suspension of an already-suspended account' do
        result = described_class.new(customer: customer, suspended: true, actor: actor).call

        expect(result.status).to eq(:no_change)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          actor: actor,
          verb: described_class::AUDIT_VERB_SUSPEND,
          target: 'ur_target_public',
          result: :success,
          detail: { outcome: 'no_change', suspended: true },
        )
      end

      # The verb still follows the direction asked for, so a filter on
      # `customer.unsuspend` finds the releases that were attempted too.
      it 'records an unsuspend attempt under the unsuspend verb' do
        allow(customer).to receive(:suspended?).and_return(false)

        described_class.new(customer: customer, suspended: false, actor: actor).call

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(verb: described_class::AUDIT_VERB_UNSUSPEND),
        )
      end
    end

    describe Onetime::Operations::Memberships::Add do
      let(:org) { double('Organization', objid: 'org-obj-1', extid: 'on_org_ext') }
      let(:customer) { double('Customer', objid: 'cust-obj-1', extid: 'ur_member') }

      # The detail carries the role the member CURRENTLY holds, not the one
      # requested — a repeat-add of 'member' against an 'admin' membership is
      # a fact worth seeing verbatim in the trail.
      it 'records a repeat-add under the normal verb, carrying the current role' do
        allow(org).to receive(:member?).with(customer).and_return(true)
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
          .with('org-obj-1', 'cust-obj-1')
          .and_return(double('OrganizationMembership', role: 'admin'))

        result = described_class.new(org: org, customer: customer, role: 'member', actor: actor).call

        expect(result.status).to eq(:no_change)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          actor: actor,
          verb: described_class::AUDIT_VERB,
          target: 'ur_member',
          result: :success,
          detail: { outcome: 'no_change', role: 'admin', org_id: 'on_org_ext' },
        )
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access)
      end
    end

    # The destructive-verb member of the family: a LIVE purge that found the
    # queue already empty is still a firing of the purge verb — raced by a
    # consumer, or double-fired — and the second wave (#4337) records it
    # rather than letting the trail depend on broker timing.
    describe Onetime::Operations::Dlq::Purge do
      let(:channel) { double('Channel', close: true, open?: false) }
      let(:connection) { double('Connection', create_channel: channel) }

      before do
        allow(Onetime::Operations::Dlq::Store).to receive(:queue_handle)
          .and_return(double('Queue', message_count: 0))
      end

      it 'records a live purge of an already-empty queue as a no-change attempt' do
        result = described_class.new(
          connection: connection, queue: 'dlq.email.message', actor: actor, dry_run: false,
        ).call

        expect(result.status).to eq(:empty)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          actor: actor,
          verb: described_class::AUDIT_VERB,
          target: 'dlq.email.message',
          result: :success,
          detail: { outcome: 'no_change', purged: 0 },
        )
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # The interplay: ops whose no-change check sits BEFORE their dry-run branch
  # ---------------------------------------------------------------------------
  # `org/entitlement_override`, `memberships/entitlement_override` and
  # `customers/change_email` can discover a no-change during a dry run, and
  # `dlq/replay` checks for an empty queue before its dry-run branch. The
  # two-trail split resolves it by intent: a live call is a mutation attempt
  # (operator trail), a dry-run call is a preview that found nothing to do
  # (observation trail, outcome marked). Asserted here once at the mechanism
  # level; each op's own spec pins its exact detail shape.
  describe 'no-change discovered during a dry run' do
    describe Onetime::Operations::Org::EntitlementOverride do
      let(:org) do
        double(
          'Organization',
          extid: 'on_org_ext',
          billing_enabled?: true,
          entitlements_grants: double('GrantsSet', to_a: ['custom_branding']),
          entitlements_revokes: double('RevokesSet', to_a: []),
          entitlements_plan: double('PlanSet', to_a: []),
          materialized_entitlements: double('MaterializedSet', to_a: ['custom_branding']),
        )
      end

      def run(dry_run:)
        described_class.new(
          org: org, action: 'grant', actor: actor,
          entitlement: 'custom_branding', dry_run: dry_run,
        ).call
      end

      it 'stays on the observation trail as a preview when discovered dry' do
        result = run(dry_run: true)

        expect(result.status).to eq(:no_change)
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
        expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
          hash_including(result: 'preview', detail: hash_including(outcome: 'no_change')),
        )
      end

      it 'lands on the operator trail when the same call is live' do
        result = run(dry_run: false)

        expect(result.status).to eq(:no_change)
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(result: :success, detail: hash_including(outcome: 'no_change')),
        )
      end
    end

    describe Onetime::Operations::Dlq::Replay do
      let(:channel) { double('Channel', close: true, open?: false) }
      let(:connection) { double('Connection', create_channel: channel) }

      before do
        allow(Onetime::Operations::Dlq::Store).to receive(:queue_handle)
          .and_return(double('Queue', message_count: 0))
      end

      def run(dry_run:)
        described_class.new(
          connection: connection, queue: 'dlq.webhooks.payload', actor: actor, dry_run: dry_run,
        ).call
      end

      it 'records a LIVE replay of an already-empty queue as a no-change attempt' do
        result = run(dry_run: false)

        expect(result.status).to eq(:empty)
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          actor: actor,
          verb: described_class::AUDIT_VERB,
          target: 'dlq.webhooks.payload',
          result: :success,
          detail: { outcome: 'no_change', replayed: 0, failed: 0 },
        )
      end

      it 'keeps a DRY-RUN of an empty queue on the observation trail' do
        result = run(dry_run: true)

        expect(result.status).to eq(:empty)
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
        expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
          actor: actor,
          verb: described_class::AUDIT_VERB,
          target: 'dlq.webhooks.payload',
          result: 'preview',
          detail: { dry_run: true, would_replay: 0, available: 0, outcome: 'no_change' },
        )
      end
    end
  end
end
