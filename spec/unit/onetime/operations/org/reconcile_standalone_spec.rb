# spec/unit/onetime/operations/org/reconcile_standalone_spec.rb
#
# frozen_string_literal: true

# Unit tests for the STANDALONE-MODE branch of Onetime::Operations::Org::Reconcile
# (#3731, decision D13). Kept in its own file because the branch is a LIVE
# BEHAVIOUR CHANGE rather than part of the extraction: before D13 a
# billing-disabled reconcile fell through to the plan engine and dead-ended at
# :skipped_no_plan, doing nothing, while
# WithPlanEntitlements#materialize_standalone_entitlements! had existed the
# whole time. It is reached through the existing colonel endpoint on every
# self-hosted install and it cascades to every membership.
#
# Two layers:
#
#   1. Mocked contract — branch precedence (billing_enabled? is checked BEFORE
#      stripe_subscription_id), the plan engine and Stripe are never touched,
#      dry run writes nothing, exactly one audit event, and the wire-critical
#      fact that `mode` stays 'entitlements_only'.
#
#   2. Real datastore — the cascade proof. Mocks cannot show that
#      materialize_standalone_entitlements! + rematerialize_all_memberships!
#      actually land in a MEMBERSHIP's materialized entitlement set: both run
#      inside Familia MULTI/EXEC blocks and the membership is re-read from the
#      datastore by OrganizationMembership.active_for_org, not from the object
#      the caller holds. Billing is disabled for every RSpec example by
#      apps/web/billing/spec/support/billing_isolation.rb, so standalone is the
#      default state here.
#
# Run: bundle exec rspec spec/unit/onetime/operations/org/reconcile_standalone_spec.rb

require 'spec_helper'
require 'onetime/models/admin_audit_event'
require 'onetime/operations/org/reconcile'

RSpec.describe Onetime::Operations::Org::Reconcile, 'standalone mode (billing disabled)' do
  let(:actor) { 'cli' } # Customers::Shared::CLI_ACTOR sentinel value

  let(:standalone_entitlements) do
    Onetime::Models::Features::WithPlanEntitlements::STANDALONE_ENTITLEMENTS
  end

  before do
    allow(Onetime::AdminAuditEvent).to receive(:record)
    # Keep the swallowed-anomaly log lines out of the spec output; asserted
    # explicitly in the degradable-cascade examples below.
    allow(OT).to receive(:le)
  end

  # ==========================================================================
  # Layer 1 — mocked contract
  # ==========================================================================

  describe 'mocked contract' do
    let(:cascade_result) { { success: 3, failed: 0, total: 3, failed_ids: [] } }

    let(:org) do
      obj = double(
        'Organization',
        objid: 'org-obj-sa',
        extid: 'on_org_sa',
        planid: '',
        billing_enabled?: false,
        stripe_subscription_id: nil,
        subscription_status: nil,
        subscription_period_end: nil,
        materialized_entitlements: double('Set', size: 0),
      )
      allow(obj).to receive(:materialize_standalone_entitlements!).and_return(true)
      allow(obj).to receive(:rematerialize_all_memberships!).and_return(cascade_result)
      obj
    end

    # The instance the op reloads after an applied run.
    let(:reloaded_org) do
      double(
        'Organization(reloaded)',
        objid: 'org-obj-sa',
        extid: 'on_org_sa',
        planid: '',
        subscription_status: nil,
        subscription_period_end: nil,
        materialized_entitlements: double('Set', size: 23),
      )
    end

    before do
      allow(Onetime::Organization).to receive(:load).with('org-obj-sa').and_return(reloaded_org)
      allow(Billing::Operations::ApplySubscriptionToOrg).to receive(:materialize_entitlements_for_org)
      allow(Billing::Operations::ApplySubscriptionToOrg).to receive(:call)
      allow(Stripe::Subscription).to receive(:retrieve)
    end

    describe 'applied' do
      subject(:result) { described_class.new(org: org, actor: actor, dry_run: false).call }

      it 'returns :standalone' do
        expect(result.status).to eq(:standalone)
      end

      # WIRE CONTRACT: colonel-organizations.ts declares
      # `mode: z.enum(['stripe_sync', 'entitlements_only'])`. A third mode string
      # would fail response validation in the admin UI on exactly the
      # billing-disabled installs this branch serves.
      it 'reports mode entitlements_only, NOT a third mode string' do
        expect(result.mode).to eq('entitlements_only')
        expect(described_class.new(org: org, actor: actor, dry_run: false).call.mode)
          .to be_one_of_reconcile_modes
      end

      it 'materializes the standalone entitlement set' do
        result
        expect(org).to have_received(:materialize_standalone_entitlements!).once
      end

      # The whole risk of D13: materialize_standalone_entitlements! writes the
      # ORG's sets only. Without this second call every member keeps a stale
      # org ∩ ROLE_ENTITLEMENTS intersection.
      it 'cascades to every active membership' do
        result
        expect(org).to have_received(:rematerialize_all_memberships!).once
      end

      it 'never reaches the plan engine' do
        result
        expect(Billing::Operations::ApplySubscriptionToOrg)
          .not_to have_received(:materialize_entitlements_for_org)
        expect(Billing::Operations::ApplySubscriptionToOrg).not_to have_received(:call)
      end

      it 'reports the cascade counts in the reason (D14: not a Result field)' do
        expect(result.reason).to eq(
          'Billing disabled: materialized STANDALONE_ENTITLEMENTS; memberships re-materialized 3/3'
        )
      end

      it 'snapshots before/after around the reload' do
        expect(result.before[:materialized_count]).to eq(0)
        expect(result.after[:materialized_count]).to eq(23)
      end

      it 'records EXACTLY ONE audit event with the unchanged verb' do
        result
        expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
          actor: actor,
          verb: 'organization.reconcile',
          target: 'on_org_sa',
          result: :success,
          detail: hash_including(mode: 'entitlements_only', status: 'standalone'),
        )
      end

      it 'is classified as an operator-visible success' do
        expect(described_class::OK_STATUSES).to include(:standalone)
      end
    end

    # billing_enabled? is checked BEFORE the stripe_subscription_id mode
    # selection. A self-hosted install that once had billing on can still carry
    # a subscription id; reconcile must not call out to Stripe there.
    describe 'branch precedence over a leftover stripe_subscription_id' do
      before { allow(org).to receive(:stripe_subscription_id).and_return('sub_leftover') }

      it 'takes the standalone branch and never contacts Stripe' do
        result = described_class.new(org: org, actor: actor, dry_run: false).call

        expect(result.status).to eq(:standalone)
        expect(result.mode).to eq('entitlements_only')
        expect(Stripe::Subscription).not_to have_received(:retrieve)
        expect(Billing::Operations::ApplySubscriptionToOrg).not_to have_received(:call)
        expect(org).to have_received(:materialize_standalone_entitlements!).once
      end
    end

    describe 'dry run' do
      subject(:result) { described_class.new(org: org, actor: actor).call } # dry_run defaults to true

      it 'returns :planned and writes nothing' do
        expect(result.status).to eq(:planned)
        expect(result.dry_run).to be(true)
        expect(result.after).to be_nil
        expect(org).not_to have_received(:materialize_standalone_entitlements!)
        expect(org).not_to have_received(:rematerialize_all_memberships!)
      end

      it 'names both halves of the change it would make' do
        expect(result.reason).to eq(
          'Billing disabled: would materialize STANDALONE_ENTITLEMENTS ' \
          'and re-materialize every active membership'
        )
      end

      it 'audits nothing and does not reload' do
        result
        expect(Onetime::AdminAuditEvent).not_to have_received(:record)
        expect(Onetime::Organization).not_to have_received(:load)
      end
    end

    # The org-level write has already committed and
    # OrganizationMembership#entitlements falls back to computing the
    # intersection on the fly, so a broken cascade is logged, not raised.
    describe 'degradable membership cascade' do
      it 'logs partial failures without changing the status' do
        allow(org).to receive(:rematerialize_all_memberships!)
          .and_return({ success: 1, failed: 2, total: 3, failed_ids: %w[mem_p mem_q] })

        result = described_class.new(org: org, actor: actor, dry_run: false).call

        expect(result.status).to eq(:standalone)
        expect(result.reason).to include('1/3')
        expect(OT).to have_received(:le).with(
          '[org-reconcile] membership re-materialization had failures',
          hash_including(memberships_failed: 2, memberships_failed_ids: %w[mem_p mem_q]),
        )
      end

      it 'swallows a raised cascade, still audits, and says so in the reason' do
        allow(org).to receive(:rematerialize_all_memberships!).and_raise(StandardError.new('boom'))

        result = nil
        expect { result = described_class.new(org: org, actor: actor, dry_run: false).call }
          .not_to raise_error

        expect(result.status).to eq(:standalone)
        expect(result.reason).to include('membership cascade failed')
        expect(Onetime::AdminAuditEvent).to have_received(:record).once
      end

      it 'logs a falsey materializer return rather than inventing a status' do
        allow(org).to receive(:materialize_standalone_entitlements!).and_return(false)

        result = described_class.new(org: org, actor: actor, dry_run: false).call

        expect(result.status).to eq(:standalone)
        expect(OT).to have_received(:le).with(
          '[org-reconcile] standalone materialization returned falsey',
          hash_including(org_extid: 'on_org_sa'),
        )
      end
    end

    describe 'billing_enabled? == true (unchanged pre-D13 behaviour)' do
      before do
        allow(org).to receive(:billing_enabled?).and_return(true)
        allow(Billing::Operations::ApplySubscriptionToOrg)
          .to receive(:materialize_entitlements_for_org)
          .and_return(
            Billing::Operations::MaterializeResult.new(
              status: :skipped_no_plan, planid: nil, entitlements_count: nil,
              source: nil, reason: 'Organization has no planid'
            )
          )
      end

      it 'still routes to the plan engine and never materializes standalone' do
        result = described_class.new(org: org, actor: actor, dry_run: false).call

        expect(result.status).to eq(:skipped_no_plan)
        expect(org).not_to have_received(:materialize_standalone_entitlements!)
        expect(Billing::Operations::ApplySubscriptionToOrg)
          .to have_received(:materialize_entitlements_for_org).with(org, dry_run: false)
      end
    end
  end

  # ==========================================================================
  # Layer 2 — real datastore. The cascade proof.
  # ==========================================================================
  #
  # Justified over mocks: rematerialize_all_memberships! re-reads memberships
  # via OrganizationMembership.active_for_org (a load_multi against the
  # datastore), and both materializers write inside Familia MULTI/EXEC. Nothing
  # short of a real round trip proves an operator-triggered reconcile reaches a
  # member's materialized set.
  #
  # Registers and tears down its own records; NEVER flushes (unit specs share
  # the test datastore with no per-example flush hook).
  describe 'real datastore', :datastore do
    let(:run_id) { "recon_sa_#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }

    let!(:owner)  { Onetime::Customer.create!(email: "#{run_id}_owner@example.com") }
    let!(:member) { Onetime::Customer.create!(email: "#{run_id}_member@example.com") }

    let!(:org) do
      Onetime::Organization.create!(
        "Standalone Reconcile #{run_id}", owner, "#{run_id}_org@example.com"
      )
    end

    # Deliberately NOT materialized: add_members_instance only creates the
    # through-record. This is the membership the cascade has to reach.
    let!(:member_membership) do
      org.add_members_instance(member, through_attrs: { role: 'member' })
    end

    def reload_membership
      Onetime::OrganizationMembership.find_by_org_customer(org.objid, member.objid)
    end

    after do
      org.destroy!    if org
      owner.destroy!  if owner
      member.destroy! if member
    rescue StandardError => ex
      warn "[reconcile_standalone_spec] teardown: #{ex.message}"
    end

    it 'starts in standalone mode with an unmaterialized member (precondition)' do
      expect(org.billing_enabled?).to be false
      expect(member_membership.entitlements_materialized?).to be false
      expect(member_membership.materialized_entitlements.to_a).to be_empty
    end

    it 'materializes STANDALONE_ENTITLEMENTS onto the org' do
      described_class.new(org: org, actor: actor, dry_run: false).call

      expect(org.materialized_entitlements.to_a.sort).to eq(standalone_entitlements.sort)
      expect(org.entitlements_materialized?).to be true
    end

    # THE CASCADE PROOF: a member that had nothing materialized ends up with
    # org.entitlements ∩ ROLE_ENTITLEMENTS['member'] written to its own set.
    it 'cascades into the membership materialized entitlement set' do
      result = described_class.new(org: org, actor: actor, dry_run: false).call
      expect(result.status).to eq(:standalone)

      reloaded = reload_membership
      expect(reloaded.entitlements_materialized?).to be true
      expect(reloaded.materialized_entitlements.to_a.sort).to eq(
        Onetime::OrganizationMembership::MEMBER_ENTITLEMENTS.to_a.sort
      )
    end

    it 'reports the real membership count in the reason' do
      result = described_class.new(org: org, actor: actor, dry_run: false).call

      # owner (from create!) + the member added above
      expect(result.reason).to eq(
        'Billing disabled: materialized STANDALONE_ENTITLEMENTS; memberships re-materialized 2/2'
      )
    end

    it 'repairs drift left in the materialized set' do
      org.materialized_entitlements.add('zzz_orphaned_drift')
      expect(org.materialized_entitlements.to_a).to include('zzz_orphaned_drift')

      described_class.new(org: org, actor: actor, dry_run: false).call

      expect(org.materialized_entitlements.to_a).not_to include('zzz_orphaned_drift')
    end

    # The invariant an adapter reimplementation would silently break: reconcile
    # re-runs plan + grants − revokes, it does not clear the override sets.
    it 'preserves an operator grant across the standalone re-materialization' do
      org.grant_entitlement('zzz_operator_grant')

      described_class.new(org: org, actor: actor, dry_run: false).call

      expect(org.entitlements_grants.to_a).to include('zzz_operator_grant')
      expect(org.materialized_entitlements.to_a).to include('zzz_operator_grant')
    end

    it 'preserves an operator revoke across the standalone re-materialization' do
      org.revoke_entitlement('api_access')

      described_class.new(org: org, actor: actor, dry_run: false).call

      expect(org.entitlements_revokes.to_a).to include('api_access')
      expect(org.materialized_entitlements.to_a).not_to include('api_access')
    end

    it 'writes nothing on a dry run' do
      result = described_class.new(org: org, actor: actor, dry_run: true).call

      expect(result.status).to eq(:planned)
      expect(reload_membership.entitlements_materialized?).to be false
    end
  end
end

# Matcher kept local: the closed mode vocabulary is a wire contract with
# src/schemas/api/internal/responses/colonel-organizations.ts, not a general
# assertion helper.
RSpec::Matchers.define :be_one_of_reconcile_modes do
  match do |actual|
    [
      Onetime::Operations::Org::Reconcile::MODE_STRIPE_SYNC,
      Onetime::Operations::Org::Reconcile::MODE_ENTITLEMENTS_ONLY,
    ].include?(actual)
  end

  failure_message do |actual|
    "expected #{actual.inspect} to be one of the two modes the admin UI zod enum accepts"
  end
end
