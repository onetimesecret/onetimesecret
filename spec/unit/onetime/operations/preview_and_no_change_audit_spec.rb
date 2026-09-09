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

# Every op in the cohort is required here, not just the ones with behavioural
# examples below: the membership assertions at the bottom walk the whole list,
# and loading all 22 is itself the check that the shared envelope resolves from
# `lib/` and from `apps/web/auth/` alike.
require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'onetime/operations/audit_attempt'
require 'onetime/operations/dlq/purge'
require 'onetime/operations/dlq/replay'
require 'onetime/operations/domains/ensure_domain_configs'
require 'onetime/operations/domains/remove'
require 'onetime/operations/domains/repair'
require 'onetime/operations/domains/transfer'
require 'onetime/operations/email/send_test'
require 'onetime/operations/email/sync_provider_feedback'
require 'onetime/operations/memberships/add'
require 'onetime/operations/memberships/entitlement_override'
require 'onetime/operations/memberships/set_role'
require 'onetime/operations/org/delete'
require 'onetime/operations/org/entitlement_override'
require 'onetime/operations/org/reconcile'
require 'onetime/operations/org/set_plan'
require 'onetime/operations/org/transfer_ownership'
require 'auth/operations/customers/change_email'
require 'auth/operations/customers/reconcile_role_index'
require 'auth/operations/customers/set_plan'
require 'auth/operations/customers/set_role'
require 'auth/operations/customers/set_suspension'
require 'auth/operations/customers/set_verification'

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

    # The one op in the cohort whose applied row and whose no-change row come
    # out of the SAME method (`record_audit_event`), so nothing structural
    # keeps them apart — only the marker does. And this admin wrapper exists
    # precisely to separate an OPERATOR verification from the self-service
    # Rodauth one, so a dropped no-op would let an operator poke repeatedly at
    # a named account's verification state behind a silent trail.
    describe Auth::Operations::Customers::SetVerification do
      let(:customer) do
        double('Customer', extid: 'ur_target_public', objid: 'cust-obj-1', role: 'customer')
      end

      before do
        allow(Auth::Operations::SetCustomerVerification).to receive(:new)
          .and_return(double('SetCustomerVerification', call: :no_change))
      end

      it 'records the attempt even though one emitter serves both paths' do
        result = described_class.new(
          customer: customer, verified: true, actor: actor, verified_by: 'colonel_admin',
        ).call

        expect(result).to eq(:no_change)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(
            actor: actor,
            verb: described_class::AUDIT_VERB,
            target: 'ur_target_public',
            result: :success,
            detail: hash_including(outcome: 'no_change'),
          ),
        )
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access)
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

    # The org-scoped twin of the customer role change above, and the reason the
    # envelope is shared rather than retyped: reaching for `owner` on a
    # membership that already holds it is the same reach for the same
    # privilege, so whether the state happened to already match must not decide
    # whether the trail shows the reach.
    describe Onetime::Operations::Memberships::SetRole do
      let(:org) { double('Organization', objid: 'org-obj-1', extid: 'on_org_ext') }
      let(:customer) { double('Customer', objid: 'cust-obj-1', extid: 'ur_member') }

      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
          .with('org-obj-1', 'cust-obj-1')
          .and_return(double('OrganizationMembership', role: 'owner', active?: true))
      end

      def no_change
        described_class.new(org: org, customer: customer, new_role: 'owner', actor: actor).call
      end

      it 'records the attempt under the normal verb, marked outcome: no_change' do
        result = no_change

        expect(result.status).to eq(:no_change)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(
            actor: actor,
            verb: described_class::AUDIT_VERB,
            target: 'ur_member',
            result: :success,
            detail: hash_including(outcome: 'no_change'),
          ),
        )
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access)
      end

      # Here the absence is the DISTINCTION, not an omission: this op's applied
      # event is fail-closed (#4333) because the membership stores only the role
      # it now holds. A no-change moved no privilege, so there is no untraceable
      # grant for a hard failure to protect — only an idempotent no-op to break.
      it 'is NOT fail-closed, unlike the applied membership role change' do
        no_change

        expect(Onetime::ColonelAuditEvent).to have_received(:record).with(hash_excluding(:fail_closed))
      end
    end

    # A billing verb, and the target is the ORG rather than the acting colonel:
    # moving a paying org onto a plan is money-adjacent, so an operator
    # re-applying the plan the org already holds must not read as silence.
    describe Onetime::Operations::Org::SetPlan do
      let(:org) { double('Organization', extid: 'on_org_ext', planid: 'identity_plus_v1') }

      it 'records a re-application of the plan the org already holds' do
        result = described_class.new(org: org, planid: 'identity_plus_v1', actor: actor).call

        expect(result.status).to eq(:no_change)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(
            actor: actor,
            verb: described_class::AUDIT_VERB,
            target: 'on_org_ext',
            result: :success,
            detail: hash_including(outcome: 'no_change'),
          ),
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

    # The membership-scoped sibling of the org op above, on the same D15
    # short-circuit. It earns its own row because a membership grant is NOT
    # bounded by the org plan or the role template — the grants set is unioned
    # on top with no intersection, so it reaches `can?` directly. "An operator
    # asked for that reach" is the fact, whether or not the set moved.
    describe Onetime::Operations::Memberships::EntitlementOverride do
      let(:org) do
        double('Organization', objid: 'org-obj-1', extid: 'on_org_ext', billing_enabled?: true)
      end
      let(:customer) { double('Customer', objid: 'cust-obj-1', extid: 'ur_member') }

      # A literal, not a constant read: this op has AUDIT_VERB_PREFIX and
      # computes the emitted verb from @action, so the string IS the assertion.
      let(:verb) { 'membership.entitlement.grant' }

      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
          .with('org-obj-1', 'cust-obj-1')
          .and_return(
            double(
              'OrganizationMembership',
              active?: true,
              entitlements_grants: double('GrantsSet', to_a: ['custom_branding']),
              entitlements_revokes: double('RevokesSet', to_a: []),
              materialized_entitlements: double('MaterializedSet', to_a: ['custom_branding']),
            ),
          )
      end

      def run(dry_run:)
        described_class.new(
          org: org, customer: customer, action: 'grant', actor: actor,
          entitlement: 'custom_branding', dry_run: dry_run,
        ).call
      end

      it 'stays on the observation trail as a preview when discovered dry' do
        result = run(dry_run: true)

        expect(result.status).to eq(:no_change)
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
        expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
          hash_including(
            actor: actor,
            verb: verb,
            target: 'ur_member',
            result: 'preview',
            detail: hash_including(dry_run: true, outcome: 'no_change'),
          ),
        )
      end

      it 'lands on the operator trail when the same grant is live' do
        result = run(dry_run: false)

        expect(result.status).to eq(:no_change)
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(
            actor: actor,
            verb: verb,
            target: 'ur_member',
            result: :success,
            detail: hash_including(outcome: 'no_change'),
          ),
        )
      end
    end

    # The highest-value account-takeover primitive an operator has, which is
    # why verb-filter completeness matters MOST here: a :no_change answer also
    # CONFIRMS the account currently holds the address that was asked for, so a
    # repeated same-address probe is exactly the pattern the trail must not go
    # quiet on. Its dry-run half is the one preview in the cohort that carries
    # the no-change marker onto the observation trail — both markers at once.
    describe Auth::Operations::Customers::ChangeEmail do
      let(:customer) do
        double('Customer', extid: 'ur_target_public', email: 'old@example.com', anonymous?: false)
      end

      def run(dry_run:)
        described_class.new(
          customer: customer, new_email: 'OLD@Example.com', actor: actor, dry_run: dry_run,
        ).call
      end

      it 'records a LIVE same-address request as a no-change attempt' do
        result = run(dry_run: false)

        expect(result.status).to eq(:no_change)
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(
            actor: actor,
            verb: described_class::AUDIT_VERB,
            target: 'ur_target_public',
            result: :success,
            detail: hash_including(outcome: 'no_change'),
          ),
        )
      end

      it 'keeps the dry-run half on the observation trail, marked BOTH ways' do
        result = run(dry_run: true)

        expect(result.status).to eq(:no_change)
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
        expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
          hash_including(
            actor: actor,
            verb: described_class::AUDIT_VERB,
            target: 'ur_target_public',
            result: 'preview',
            detail: hash_including(dry_run: true, outcome: 'no_change'),
          ),
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

  # ---------------------------------------------------------------------------
  # The envelope itself (#4366)
  # ---------------------------------------------------------------------------
  # Everything above asserts the envelope one op at a time, which is how the
  # feature was built: 28 hand-written kwarg lists that had to agree with each
  # other, and CI would happily accept the tenth op getting one of them wrong.
  # These examples assert it ONCE, against the module that now produces it, so
  # the three fields the whole feature rests on hold by construction:
  #
  #   1. WHICH TRAIL — chosen by which method you call, not by a kwarg.
  #   2. THE MARKER — merged last, so a call site cannot displace it.
  #   3. NO `fail_closed` — there is no parameter for it to pass.
  #
  describe Onetime::Operations::AuditAttempt do
    # A minimal host: the module plus the hooks an op supplies. Deliberately not
    # a real op — the point here is the envelope, and every op's own detail is
    # already pinned above or in its own spec.
    let(:host_class) do
      Class.new do
        include Onetime::Operations::AuditAttempt

        def initialize(actor:, target:)
          @actor  = actor
          @target = target
        end

        def audit_target = @target

        # The module's methods are private, exactly as an op's callers see them,
        # so the examples reach them through shims rather than `send`.
        def no_change(detail = {}) = record_no_change_attempt(detail)
        def preview(detail = {})   = record_preview_observation(detail)
      end.tap { |klass| klass.const_set(:AUDIT_VERB, 'test.envelope') }
    end

    let(:host) { host_class.new(actor: actor, target: 'tg_public') }

    it 'puts a no-change attempt on the OPERATOR trail under the op verb' do
      host.no_change(purged: 0)

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'test.envelope',
        target: 'tg_public',
        result: :success,
        detail: { purged: 0, outcome: 'no_change' },
      )
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access)
    end

    it 'puts a preview on the OBSERVATION trail under the same op verb' do
      host.preview(count: 42)

      expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
        actor: actor,
        verb: 'test.envelope',
        target: 'tg_public',
        result: 'preview',
        detail: { count: 42, dry_run: true },
      )
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end

    # The invariant #4333 leaves to this module: a no-change destroyed nothing,
    # so there is no irrecoverable fact for a hard failure to surface. All
    # fail-closing an idempotent no-op could do is fail an operation that had
    # already succeeded by doing nothing. Asserted against the method's ARITY
    # rather than the emitted kwargs, because the guarantee is that no op can
    # opt in even by accident.
    it 'exposes no fail_closed parameter, so a no-change row cannot be fail-closed' do
      expect(described_class.instance_method(:record_no_change_attempt).parameters)
        .to eq([[:opt, :detail]])

      host.no_change(purged: 0)

      expect(Onetime::ColonelAuditEvent).to have_received(:record).with(hash_excluding(:fail_closed))
    end

    # The marker is what every verb-filter query keys off to tell an ATTEMPT
    # from an EFFECT, so a call site does not get to overwrite it — the merge
    # order in the module puts the marker last on purpose.
    it 'will not let a call site displace the no_change marker' do
      host.no_change(outcome: 'applied')

      expect(Onetime::ColonelAuditEvent).to have_received(:record)
        .with(hash_including(detail: { outcome: 'no_change' }))
    end

    it 'will not let a call site displace the dry_run marker' do
      host.preview(dry_run: false)

      expect(Onetime::ColonelAuditEvent).to have_received(:record_access)
        .with(hash_including(detail: { dry_run: true }))
    end

    # `AuditReason#with_reason` returns nil for a nil detail when no reason was
    # given, so the two modules have to compose without the envelope blowing up.
    it 'tolerates a nil detail, so with_reason composes with it' do
      host.no_change(nil)

      expect(Onetime::ColonelAuditEvent).to have_received(:record)
        .with(hash_including(detail: { outcome: 'no_change' }))
    end

    # Three ops compute their verb rather than reading a constant
    # (`customers/set_suspension` by direction, both `entitlement_override`s
    # from `@action`). A class-body definition wins over an included module's,
    # which is why the hook is named for what those ops already called it.
    it 'lets an op whose verb is computed override the AUDIT_VERB default' do
      computed = Class.new(host_class) do
        def audit_verb = 'test.computed'
      end

      computed.new(actor: actor, target: 'tg_public').no_change

      expect(Onetime::ColonelAuditEvent).to have_received(:record)
        .with(hash_including(verb: 'test.computed'))
    end

    # No default target, on purpose: an op that forgets the hook should fail
    # loudly on its first emit rather than record a row against nil.
    it 'raises rather than recording a row against a nil target' do
      forgetful = Class.new do
        include Onetime::Operations::AuditAttempt

        def go = record_no_change_attempt({})
      end
      forgetful.const_set(:AUDIT_VERB, 'test.forgetful')

      expect { forgetful.new.go }.to raise_error(NotImplementedError, /audit_target/)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end

  # ---------------------------------------------------------------------------
  # Cohort membership (#4366)
  # ---------------------------------------------------------------------------
  # The gap the per-op examples above cannot close: they pin the ops they know
  # about, and say nothing about the fourteenth op someone adds next quarter.
  # These two walk the whole cohort, so an op that hand-rolls the envelope
  # again is a CI failure rather than a review miss.
  describe 'the #4337 cohort' do
    let(:cohort) do
      [
        Auth::Operations::Customers::ChangeEmail,
        Auth::Operations::Customers::ReconcileRoleIndex,
        Auth::Operations::Customers::SetPlan,
        Auth::Operations::Customers::SetRole,
        Auth::Operations::Customers::SetSuspension,
        Auth::Operations::Customers::SetVerification,
        Onetime::Operations::Dlq::Purge,
        Onetime::Operations::Dlq::Replay,
        Onetime::Operations::Domains::EnsureDomainConfigs,
        Onetime::Operations::Domains::Remove,
        Onetime::Operations::Domains::Repair,
        Onetime::Operations::Domains::Transfer,
        Onetime::Operations::Email::SendTest,
        Onetime::Operations::Email::SyncProviderFeedback,
        Onetime::Operations::Memberships::Add,
        Onetime::Operations::Memberships::EntitlementOverride,
        Onetime::Operations::Memberships::SetRole,
        Onetime::Operations::Org::Delete,
        Onetime::Operations::Org::EntitlementOverride,
        Onetime::Operations::Org::Reconcile,
        Onetime::Operations::Org::SetPlan,
        Onetime::Operations::Org::TransferOwnership,
      ]
    end

    it 'composes the shared envelope in every op' do
      missing = cohort.reject { |op| op.include?(Onetime::Operations::AuditAttempt) }

      expect(missing).to be_empty
    end

    # The module has no default target, so every op owes one. Checked
    # structurally rather than by calling it, since building 22 ops here would
    # duplicate 22 specs' worth of fixtures to learn nothing extra.
    it 'supplies the target hook in every op, since the module has no default' do
      missing = cohort.reject do |op|
        (op.private_instance_methods(false) + op.instance_methods(false)).include?(:audit_target)
      end

      expect(missing).to be_empty
    end

    # The three whose verb is not a single constant must say so themselves.
    it 'overrides the verb hook wherever the verb is not a bare AUDIT_VERB' do
      computed = [
        Auth::Operations::Customers::SetSuspension,
        Onetime::Operations::Memberships::EntitlementOverride,
        Onetime::Operations::Org::EntitlementOverride,
      ]
      missing = computed.reject { |op| op.private_instance_methods(false).include?(:audit_verb) }

      expect(missing).to be_empty

      # And the other nineteen must carry the constant the default hook reads.
      constant_verb = (cohort - computed).reject { |op| op.const_defined?(:AUDIT_VERB, false) }

      expect(constant_verb).to be_empty
    end
  end
end
