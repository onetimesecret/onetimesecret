# spec/cli/billing/sync_org_command_spec.rb
#
# frozen_string_literal: true

# CLI adapter tests for `bin/ots billing sync-org` (#3903).
#
# `billing sync-org` is a billing-namespace alias over the same audited
# Onetime::Operations::Org::Reconcile op as `org reconcile`. The mutation and
# its single AdminAuditEvent are the op's job — covered by
# spec/unit/onetime/operations/org/reconcile_spec.rb. Here the op is stubbed
# at its constructor (same approach as spec/cli/org_command_spec.rb) so these
# stay pure adapter tests: op construction, status -> stats mapping, per-org
# error containment in the --all sweep, and the audit non-authorship contract
# ("Adapters MUST NOT audit", reconcile.rb).
#
# Run: bundle exec rspec spec/cli/billing/sync_org_command_spec.rb

require_relative '../cli_spec_helper'
# The command file is also auto-discovered by lib/onetime/cli.rb's apps glob;
# required explicitly (like the test_trigger_webhook peer spec) so this spec
# does not depend on the discovery cwd. It pulls in the Reconcile op and the
# Customers::Shared CLI_ACTOR sentinel via its own requires.
require_relative '../../../apps/web/billing/cli/sync_org_command'

RSpec.describe Onetime::CLI::BillingSyncOrgCommand, type: :cli do
  subject(:cmd) { described_class.new }

  let(:org) do
    double('Organization', extid: 'on_org_ext_12345', stripe_subscription_id: 'sub_123')
  end

  let(:ok_result) do
    Onetime::Operations::Org::Reconcile::Result.new(
      status: :applied,
      org_id: 'on_org_ext_12345',
      mode: 'stripe_sync',
      before: {
        planid: 'free_v1', subscription_status: nil,
        subscription_period_end: nil, materialized_count: 2
      },
      after: {
        planid: 'identity_plus_v1', subscription_status: 'active',
        subscription_period_end: nil, materialized_count: 7
      },
      reason: nil,
      dry_run: false,
    )
  end

  let(:operation) { instance_double(Onetime::Operations::Org::Reconcile, call: ok_result) }

  before do
    # Don't boot the real application; skip the Stripe key/config side effects.
    allow(cmd).to receive(:boot_application!)
    allow(cmd).to receive(:stripe_configured?).and_return(true)

    allow(Onetime::Organization).to receive(:find_by_extid).and_return(nil)
    allow(Onetime::Organization).to receive(:find_by_extid).with('on_org_ext_12345').and_return(org)
    allow(Onetime::Operations::Org::Reconcile).to receive(:new).and_return(operation)
  end

  describe 'op construction (single org)' do
    it 'constructs the op with org:, the CLI sentinel actor, and dry_run: false' do
      capture_output { cmd.call(extid: 'on_org_ext_12345') }

      expect(Onetime::Operations::Org::Reconcile).to have_received(:new).with(
        org: org,
        actor: Onetime::CLI::Customers::Shared::CLI_ACTOR,
        dry_run: false,
      )
    end

    it "attributes the audit actor to the shared 'cli' sentinel, never a Customer" do
      capture_output { cmd.call(extid: 'on_org_ext_12345') }

      expect(Onetime::Operations::Org::Reconcile).to have_received(:new)
        .with(hash_including(actor: 'cli'))
    end

    it 'passes dry_run: true through for --dry-run' do
      capture_output { cmd.call(extid: 'on_org_ext_12345', dry_run: true) }

      expect(Onetime::Operations::Org::Reconcile).to have_received(:new)
        .with(hash_including(dry_run: true))
    end
  end

  describe 'status -> stats mapping' do
    it 'treats an OK_STATUSES result as synced and prints the planid diff' do
      output = capture_output { cmd.call(extid: 'on_org_ext_12345') }

      expect(output[:stdout]).to include('Synced on_org_ext_...: free_v1 -> identity_plus_v1')
    end

    it 'prints the dry-run line when the op returns an OK status with no after snapshot' do
      allow(operation).to receive(:call).and_return(
        ok_result.with(status: :planned, after: nil, reason: 'would apply identity_plus_v1', dry_run: true)
      )

      output = capture_output { cmd.call(extid: 'on_org_ext_12345', dry_run: true) }

      expect(output[:stdout]).to include('[DRY RUN] on_org_ext_...: planned')
      expect(output[:stdout]).to include('would apply identity_plus_v1')
    end

    it 'appends result.reason to the synced line when present' do
      # :standalone is the case that motivates this: before/after planid are
      # identical (billing disabled), so without the reason the line reads
      # like a no-op — and reason is the ONLY carrier of the membership
      # cascade outcome, including its failure string (reconcile.rb D14).
      allow(operation).to receive(:call).and_return(
        ok_result.with(
          status: :standalone,
          after: ok_result.before,
          reason: 'Billing disabled: materialized STANDALONE_ENTITLEMENTS; membership cascade failed (see logs)',
        )
      )

      output = capture_output { cmd.call(extid: 'on_org_ext_12345') }

      expect(output[:stdout]).to include(
        'Synced on_org_ext_...: free_v1 -> free_v1 ' \
        '(Billing disabled: materialized STANDALONE_ENTITLEMENTS; membership cascade failed (see logs))'
      )
    end

    it 'counts a :stripe_error result toward errors without raising' do
      allow(operation).to receive(:call).and_return(
        ok_result.with(status: :stripe_error, after: nil, reason: 'no such subscription')
      )
      allow(Onetime::Organization).to receive(:instances).and_return(
        double('Instances').tap { |inst| allow(inst).to receive(:each_record).and_yield(org) }
      )

      output = nil
      expect { output = capture_output { cmd.call(all: true) } }.not_to raise_error

      expect(output[:stdout]).to include('Error on_org_ext_...: stripe_error (no such subscription)')
      expect(output[:stdout]).to include('Summary: 0 synced, 0 skipped, 1 errors')
    end
  end

  describe '--all sweep error containment' do
    let(:org_a) { double('OrgA', extid: 'on_org_aaa_12345', stripe_subscription_id: 'sub_a') }
    let(:org_b) { double('OrgB', extid: 'on_org_bbb_12345', stripe_subscription_id: 'sub_b') }
    let(:instances) { double('Instances') }
    let(:op_a) { instance_double(Onetime::Operations::Org::Reconcile) }
    let(:op_b) { instance_double(Onetime::Operations::Org::Reconcile, call: ok_result) }

    before do
      allow(Onetime::Organization).to receive(:instances).and_return(instances)
      allow(instances).to receive(:each_record).and_yield(org_a).and_yield(org_b)

      allow(Onetime::Operations::Org::Reconcile).to receive(:new)
        .with(hash_including(org: org_a)).and_return(op_a)
      allow(Onetime::Operations::Org::Reconcile).to receive(:new)
        .with(hash_including(org: org_b)).and_return(op_b)
    end

    # CatalogMissError and PlanCacheMissError are Billing::OpsProblem
    # subclasses, not Stripe::StripeError, so they escape Reconcile#call and
    # must be contained per-org (the adapter rescues the parent class).

    it 'contains a CatalogMissError per-org and still processes the next org' do
      allow(op_a).to receive(:call)
        .and_raise(Billing::CatalogMissError.new(price_id: 'price_ghost'))

      output = capture_output { cmd.call(all: true) }

      expect(output[:stdout]).to include(
        'Error on_org_aaa_...: Billing::CatalogMissError: Price ID not found in catalog: price_ghost'
      )
      expect(output[:stdout]).to include('Synced on_org_bbb_...: free_v1 -> identity_plus_v1')
      expect(output[:stdout]).to include('Summary: 1 synced, 0 skipped, 1 errors')
    end

    it 'contains a PlanCacheMissError per-org and still processes the next org' do
      # Raised by ApplySubscriptionToOrg#materialize_entitlements on
      # plan-cache/catalog drift — previously escaped the CatalogMissError-only
      # rescue and aborted the sweep with a raw backtrace.
      allow(op_a).to receive(:call)
        .and_raise(Billing::PlanCacheMissError.new(plan_id: 'ghost_plan_v1'))

      output = nil
      expect { output = capture_output { cmd.call(all: true) } }.not_to raise_error

      expect(output[:stdout]).to include(
        'Error on_org_aaa_...: Billing::PlanCacheMissError: Plan not found in cache or config: ghost_plan_v1'
      )
      expect(output[:stdout]).to include('Synced on_org_bbb_...: free_v1 -> identity_plus_v1')
      expect(output[:stdout]).to include('Summary: 1 synced, 0 skipped, 1 errors')
    end

    # Containment scope decision (PR #3924 review): sweep robust, single-org
    # loud. An unexpected exception must not abort a --all run mid-flight with
    # no summary, but the same exception on `sync-org <extid>` must still
    # raise so the operator gets the full backtrace.

    it 'contains an unexpected StandardError per-org and still reaches the summary' do
      allow(op_a).to receive(:call).and_raise(ArgumentError, 'bad org field')

      output = nil
      expect { output = capture_output { cmd.call(all: true) } }.not_to raise_error

      expect(output[:stdout]).to include('Error on_org_aaa_...: ArgumentError: bad org field')
      expect(output[:stdout]).to include('Synced on_org_bbb_...: free_v1 -> identity_plus_v1')
      expect(output[:stdout]).to include('Summary: 1 synced, 0 skipped, 1 errors')
    end

    it 'stays fail-loud for a non-OpsProblem exception on the single-org path' do
      allow(Onetime::Operations::Org::Reconcile).to receive(:new)
        .with(hash_including(org: org)).and_return(op_a)
      allow(op_a).to receive(:call).and_raise(ArgumentError, 'bad org field')

      expect {
        capture_output { cmd.call(extid: 'on_org_ext_12345') }
      }.to raise_error(ArgumentError, 'bad org field')
    end
  end

  describe 'audit non-authorship' do
    it 'never records an AdminAuditEvent from the adapter (the op owns the single audit)' do
      allow(Onetime::AdminAuditEvent).to receive(:record)

      capture_output { cmd.call(extid: 'on_org_ext_12345') }

      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end
  end
end
