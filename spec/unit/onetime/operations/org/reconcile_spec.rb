# spec/unit/onetime/operations/org/reconcile_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Operations::Org::Reconcile (#3731).
#
# Mocked contract, no datastore: mode selection, status routing straight off
# Billing::Operations::MaterializeResult, dry-run writes-nothing, the
# exactly-once audit event, the Stripe-failure-returns-a-status guardrail, and
# the negative assertion that reconcile NEVER clears the operator override sets
# (entitlements_grants / entitlements_revokes) — the single invariant an adapter
# reimplementation would silently break.
#
# The engine itself (ApplySubscriptionToOrg -> apply_entitlements' MULTI/EXEC)
# is stubbed at the class boundary; it has its own coverage in
# apps/web/billing/spec.
#
# Run: bundle exec rspec spec/unit/onetime/operations/org/reconcile_spec.rb

require 'spec_helper'
require 'onetime/models/admin_audit_event'
require 'onetime/operations/org/reconcile'

RSpec.describe Onetime::Operations::Org::Reconcile do
  let(:actor) { 'ur_col_public_extid' } # PUBLIC identity (extid/email)

  let(:grants)  { double('EntitlementsGrants', size: 1, clear: nil) }
  let(:revokes) { double('EntitlementsRevokes', size: 0, clear: nil) }

  # Pre-run org. `stripe_subscription_id` is overridden per-context.
  let(:org) do
    double(
      'Organization',
      objid: 'org-obj-1',
      extid: 'on_org_ext',
      planid: 'free_v1',
      stripe_subscription_id: nil,
      subscription_status: nil,
      subscription_period_end: nil,
      # Billing-enabled is the default here; the standalone (!billing_enabled?)
      # branch is covered in reconcile_standalone_spec.rb.
      billing_enabled?: true,
      materialized_entitlements: double('Set', size: 2),
      entitlements_grants: grants,
      entitlements_revokes: revokes,
    )
  end

  # The instance the op reloads after an applied run.
  let(:reloaded_org) do
    double(
      'Organization(reloaded)',
      objid: 'org-obj-1',
      extid: 'on_org_ext',
      planid: 'identity_plus_v1',
      subscription_status: 'active',
      subscription_period_end: '1800000000',
      materialized_entitlements: double('Set', size: 7),
      entitlements_grants: grants,
      entitlements_revokes: revokes,
    )
  end

  let(:materialize_result) do
    Billing::Operations::MaterializeResult.new(
      status: :materialized,
      planid: 'free_v1',
      entitlements_count: 7,
      source: :config,
      reason: nil,
    )
  end

  before do
    allow(Onetime::AdminAuditEvent).to receive(:record)
    allow(Onetime::Organization).to receive(:load).with('org-obj-1').and_return(reloaded_org)
    allow(Billing::Operations::ApplySubscriptionToOrg)
      .to receive(:materialize_entitlements_for_org).and_return(materialize_result)
    allow(Billing::Operations::ApplySubscriptionToOrg).to receive(:call).and_return(true)
  end

  describe 'entitlements-only mode (no stripe_subscription_id)' do
    it 'applies via the billing engine and returns the engine status verbatim' do
      result = described_class.new(org: org, actor: actor, dry_run: false).call

      expect(result.status).to eq(:materialized)
      expect(result.mode).to eq('entitlements_only')
      expect(result.org_id).to eq('on_org_ext')
      expect(result.dry_run).to be(false)
      expect(Billing::Operations::ApplySubscriptionToOrg)
        .to have_received(:materialize_entitlements_for_org).with(org, dry_run: false).once
      expect(Billing::Operations::ApplySubscriptionToOrg).not_to have_received(:call)
    end

    it 'snapshots before/after around the reload' do
      result = described_class.new(org: org, actor: actor, dry_run: false).call

      expect(result.before).to eq(
        planid: 'free_v1',
        subscription_status: nil,
        subscription_period_end: nil,
        materialized_count: 2,
      )
      expect(result.after).to eq(
        planid: 'identity_plus_v1',
        subscription_status: 'active',
        subscription_period_end: '1800000000',
        materialized_count: 7,
      )
    end

    it 'records EXACTLY ONE audit event (public actor + org extid target)' do
      described_class.new(org: org, actor: actor, dry_run: false).call

      expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'organization.reconcile',
        target: 'on_org_ext',
        result: :success,
        detail: hash_including(mode: 'entitlements_only', status: 'materialized'),
      )
    end

    it 'uses the byte-identical audit verb the pre-extraction colonel emitted' do
      expect(described_class::AUDIT_VERB).to eq('organization.reconcile')
    end

    # Extraction fidelity: the pre-extraction colonel recorded an event after
    # every non-raising reconcile, including the no-op statuses. Suppressing
    # those would silently change the trail (and break the colonel tryout gate).
    {
      skipped_no_plan: 'Organization has no planid',
      plan_not_found: "Plan 'zzz' not in cache or config",
      skipped_fresh: 'Entitlements already materialized and not stale',
    }.each do |engine_status, reason|
      it "passes :#{engine_status} through with its reason and still audits" do
        allow(Billing::Operations::ApplySubscriptionToOrg)
          .to receive(:materialize_entitlements_for_org)
          .and_return(
            Billing::Operations::MaterializeResult.new(
              status: engine_status, planid: nil, entitlements_count: nil,
              source: nil, reason: reason
            )
          )

        result = described_class.new(org: org, actor: actor, dry_run: false).call

        expect(result.status).to eq(engine_status)
        expect(result.reason).to eq(reason)
        expect(Onetime::AdminAuditEvent).to have_received(:record).once
      end
    end

    it 'passes :materialized through with reason still nil (no synthesis)' do
      # Synthesis is keyed on status == :would_materialize, not on reason.nil?
      # alone — :materialized is the engine's other nil-reason status and must
      # come through untouched.
      allow(Billing::Operations::ApplySubscriptionToOrg)
        .to receive(:materialize_entitlements_for_org)
        .and_return(
          Billing::Operations::MaterializeResult.new(
            status: :materialized, planid: 'identity_plus_v1',
            entitlements_count: 7, source: :cache, reason: nil
          )
        )

      result = described_class.new(org: org, actor: actor, dry_run: false).call

      expect(result.status).to eq(:materialized)
      expect(result.reason).to be_nil
    end

    it 'previews with dry_run: true — no audit, no after snapshot' do
      allow(Billing::Operations::ApplySubscriptionToOrg)
        .to receive(:materialize_entitlements_for_org)
        .and_return(
          Billing::Operations::MaterializeResult.new(
            status: :would_materialize, planid: 'free_v1', entitlements_count: 7,
            source: :config, reason: nil
          )
        )

      result = described_class.new(org: org, actor: actor).call # dry_run defaults to true

      expect(result.status).to eq(:would_materialize)
      expect(result.dry_run).to be(true)
      expect(result.after).to be_nil
      expect(Billing::Operations::ApplySubscriptionToOrg)
        .to have_received(:materialize_entitlements_for_org).with(org, dry_run: true)
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
      expect(Onetime::Organization).not_to have_received(:load)
    end

    it 'synthesizes a human-readable reason for :would_materialize' do
      # The engine hardcodes reason: nil on :would_materialize
      # (apply_subscription_to_org.rb, would_materialize_result), so without
      # synthesis a dry run has nothing for adapters to print. The op builds
      # the reason from the MaterializeResult fields it otherwise discards —
      # reason stays the human-readable carrier (D14), no structured fields.
      allow(Billing::Operations::ApplySubscriptionToOrg)
        .to receive(:materialize_entitlements_for_org)
        .and_return(
          Billing::Operations::MaterializeResult.new(
            status: :would_materialize, planid: 'identity_plus_month',
            entitlements_count: 12, source: :config, reason: nil
          )
        )

      result = described_class.new(org: org, actor: actor).call

      expect(result.reason).to eq('Would materialize 12 entitlements for plan identity_plus_month')
    end

    it 'defaults to dry_run: true' do
      described_class.new(org: org, actor: actor).call

      expect(Billing::Operations::ApplySubscriptionToOrg)
        .to have_received(:materialize_entitlements_for_org).with(org, dry_run: true)
    end
  end

  describe 'stripe_sync mode (stripe_subscription_id present)' do
    let(:subscription) { double('Stripe::Subscription', id: 'sub_123') }

    before do
      allow(org).to receive(:stripe_subscription_id).and_return('sub_123')
      allow(Stripe::Subscription).to receive(:retrieve).and_return(subscription)
    end

    it 'retrieves the live subscription and applies it via the shared engine' do
      result = described_class.new(org: org, actor: actor, dry_run: false).call

      expect(result.status).to eq(:applied)
      expect(result.mode).to eq('stripe_sync')
      expect(result.reason).to be_nil
      expect(Stripe::Subscription).to have_received(:retrieve).with(
        id: 'sub_123',
        expand: ['items.data.price.product'],
      )
      expect(Billing::Operations::ApplySubscriptionToOrg)
        .to have_received(:call).with(org, subscription, owner: true).once
    end

    it 'records EXACTLY ONE audit event with mode stripe_sync' do
      described_class.new(org: org, actor: actor, dry_run: false).call

      expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
        hash_including(
          verb: 'organization.reconcile',
          target: 'on_org_ext',
          detail: hash_including(mode: 'stripe_sync', status: 'applied'),
        )
      )
    end

    it 'previews as :planned without calling Stripe or the engine' do
      result = described_class.new(org: org, actor: actor, dry_run: true).call

      expect(result.status).to eq(:planned)
      expect(result.mode).to eq('stripe_sync')
      expect(result.after).to be_nil
      expect(result.reason).to include('sub_123')
      expect(Stripe::Subscription).not_to have_received(:retrieve)
      expect(Billing::Operations::ApplySubscriptionToOrg).not_to have_received(:call)
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end

    it 'returns :stripe_error instead of raising, and audits nothing' do
      allow(Stripe::Subscription).to receive(:retrieve).and_raise(Stripe::StripeError.new('no such subscription'))

      result = nil
      expect { result = described_class.new(org: org, actor: actor, dry_run: false).call }.not_to raise_error

      expect(result.status).to eq(:stripe_error)
      expect(result.reason).to eq('no such subscription')
      expect(result.after).to be_nil
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end
  end

  describe 'operator override preservation (the invariant)' do
    it 'never clears entitlements_grants / entitlements_revokes on the applied entitlements path' do
      described_class.new(org: org, actor: actor, dry_run: false).call

      expect(grants).not_to have_received(:clear)
      expect(revokes).not_to have_received(:clear)
    end

    it 'never clears entitlements_grants / entitlements_revokes on the applied stripe path' do
      allow(org).to receive(:stripe_subscription_id).and_return('sub_123')
      allow(Stripe::Subscription).to receive(:retrieve).and_return(double('Stripe::Subscription'))

      described_class.new(org: org, actor: actor, dry_run: false).call

      expect(grants).not_to have_received(:clear)
      expect(revokes).not_to have_received(:clear)
    end
  end

  describe 'OK_STATUSES' do
    it 'classifies the statuses an adapter should treat as success' do
      # :standalone is the billing-disabled (self-hosted) outcome — entitlements
      # were materialized from the standalone set rather than a plan. It is a
      # success, not a skip. See reconcile_standalone_spec.rb.
      expect(described_class::OK_STATUSES).to contain_exactly(
        :applied, :materialized, :skipped_fresh, :planned, :would_materialize,
        :standalone
      )
    end
  end
end
