# spec/unit/onetime/jobs/scheduled/maintenance/entitlement_materialize_job_spec.rb
#
# frozen_string_literal: true

# EntitlementMaterializeJob Test Suite
#
# Tests the scheduled maintenance job that re-materializes org entitlements
# from the plan catalog nightly (issue #4203).
#
# Test Categories:
#
#   1. Scheduling (Unit)
#      - Requires BOTH jobs.maintenance.enabled AND the job's own flag
#      - Strict boolean check: non-boolean truthy values do not enable
#      - Registers a cron job with the configured pattern
#      - Falls back to MaintenanceJob's default cron when key absent
#
#   2. Skip Behavior (Unit)
#      - Skips when no Stripe API key configured (standalone mode)
#
#   3. Fail-Closed Abort Paths (Unit)
#      - Catalog pull failure aborts without materializing
#      - Catalog pull raising aborts without materializing
#      - Catalog pull succeeding but unverified (empty Stripe catalog is a
#        successful no-op that leaves the old cache in place) aborts without
#        materializing — the gate is catalog_verified, not success
#
#   4. Success Path (Unit)
#      - Materializes with include_memberships: true
#      - Copies result counts into the structured report
#
#   5. Failure Logging (Unit)
#      - Per-org failures land in report[:errors] and log at ERROR
#
# Run with: tests/lanes/run unit --only spec/unit/onetime/jobs/scheduled/maintenance/entitlement_materialize_job_spec.rb

require 'billing/spec/support/billing_spec_helper'
require 'rufus-scheduler'
require 'onetime/jobs/scheduled/maintenance/entitlement_materialize_job'

# The job references MaterializePlans only at run time; nothing in the unit
# process loads it, so require it here to build real result objects.
require_relative '../../../../../../apps/web/billing/operations/materialize_plans'

RSpec.describe Onetime::Jobs::Scheduled::Maintenance::EntitlementMaterializeJob, type: :billing do
  let(:scheduler) { instance_double(Rufus::Scheduler) }
  let(:logger) { instance_double(SemanticLogger::Logger) }

  # Helper to create Result objects matching Pull::Result signature.
  #
  # catalog_verified defaults to the realistic pairing — a real Pull only
  # reports a verified catalog when it persisted at least one plan — so
  # ordinary examples need not spell it out. Pass it explicitly to build the
  # divergent case the fail-closed gate exists for: success with nothing
  # verified.
  def make_pull_result(success:, plans_synced: 0, catalog_verified: nil, errors: [], error_type: nil)
    catalog_verified = success && plans_synced.positive? if catalog_verified.nil?

    Billing::Operations::Catalog::Pull::Result.new(
      success: success,
      plans_synced: plans_synced,
      catalog_verified: catalog_verified,
      errors: errors,
      error_type: error_type
    )
  end

  # Helper to create real MaterializePlansResult Data instances
  def make_materialize_result(**overrides)
    defaults = {
      scanned: 0,
      succeeded: 0,
      failed: 0,
      skipped_no_plan: 0,
      skipped_plan_filter: 0,
      memberships_succeeded: 0,
      memberships_failed: 0,
      orgs_cascaded: 0,
      errors: [],
    }
    Billing::Operations::MaterializePlansResult.new(**defaults.merge(overrides))
  end

  def stub_maintenance_conf(master:, job:)
    allow(OT).to receive(:conf).and_return({
      'jobs' => {
        'maintenance' => {
          'enabled' => master,
          'entitlement_materialize' => job,
        },
      },
    })
  end

  before do
    # Stub scheduler_logger on the class
    allow(described_class).to receive(:scheduler_logger).and_return(logger)
    allow(logger).to receive(:info)
    allow(logger).to receive(:debug)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
  end

  describe '.schedule' do
    context 'when both master and job flags are true' do
      before do
        stub_maintenance_conf(master: true, job: { 'enabled' => true, 'cron' => '0 3 * * *' })
      end

      it 'registers a cron job with the configured pattern' do
        expect(scheduler).to receive(:cron).with('0 3 * * *')
        described_class.schedule(scheduler)
      end

      it 'logs scheduling message' do
        allow(scheduler).to receive(:cron)
        expect(logger).to receive(:info).with('[EntitlementMaterializeJob] Scheduling with cron: 0 3 * * *')
        described_class.schedule(scheduler)
      end
    end

    context 'when cron key is absent' do
      before do
        stub_maintenance_conf(master: true, job: { 'enabled' => true })
      end

      it 'falls back to the MaintenanceJob default cron' do
        expect(scheduler).to receive(:cron).with('0 4 * * *')
        described_class.schedule(scheduler)
      end
    end

    context 'when master maintenance flag is false' do
      before do
        stub_maintenance_conf(master: false, job: { 'enabled' => true })
      end

      it 'does not register any job even with job flag true' do
        expect(scheduler).not_to receive(:cron)
        described_class.schedule(scheduler)
      end
    end

    context 'when job flag is false' do
      before do
        stub_maintenance_conf(master: true, job: { 'enabled' => false })
      end

      it 'does not register any job' do
        expect(scheduler).not_to receive(:cron)
        described_class.schedule(scheduler)
      end
    end

    context 'when job flag is a non-boolean truthy value' do
      it "does not register for 'true' string" do
        stub_maintenance_conf(master: true, job: { 'enabled' => 'true' })
        expect(scheduler).not_to receive(:cron)
        described_class.schedule(scheduler)
      end

      it "does not register for 'yes' string" do
        stub_maintenance_conf(master: true, job: { 'enabled' => 'yes' })
        expect(scheduler).not_to receive(:cron)
        described_class.schedule(scheduler)
      end
    end

    context 'when config is missing' do
      before do
        allow(OT).to receive(:conf).and_return({})
      end

      it 'does not register any job' do
        expect(scheduler).not_to receive(:cron)
        described_class.schedule(scheduler)
      end
    end
  end

  describe '.run_materialization (via send)' do
    let(:report) { {} }

    describe 'skip behavior' do
      context 'when no Stripe API key configured' do
        before do
          allow(Onetime.billing_config).to receive(:stripe_key).and_return(nil)
        end

        it 'records skip in report, logs debug, and calls neither operation' do
          expect(logger).to receive(:debug).with('[EntitlementMaterializeJob] Skipping: No Stripe API key configured')
          expect(Billing::Operations::Catalog::Pull).not_to receive(:call)
          expect(Billing::Operations::MaterializePlans).not_to receive(:call)

          described_class.send(:run_materialization, report)

          expect(report[:skipped]).to eq('no_stripe_key')
        end
      end

      context 'when Stripe API key is blank string' do
        before do
          allow(Onetime.billing_config).to receive(:stripe_key).and_return('   ')
        end

        it 'records skip in report and calls neither operation' do
          expect(Billing::Operations::Catalog::Pull).not_to receive(:call)
          expect(Billing::Operations::MaterializePlans).not_to receive(:call)

          described_class.send(:run_materialization, report)

          expect(report[:skipped]).to eq('no_stripe_key')
        end
      end
    end

    context 'with a Stripe API key configured' do
      before do
        allow(Onetime.billing_config).to receive(:stripe_key).and_return('sk_test_123')
      end

      describe 'fail-closed abort when catalog pull fails' do
        it 'aborts without materializing and logs at ERROR' do
          pull_result = make_pull_result(success: false, errors: ['API rate limit exceeded'], error_type: :stripe_api)
          allow(Billing::Operations::Catalog::Pull).to receive(:call).and_return(pull_result)

          expect(Billing::Operations::MaterializePlans).not_to receive(:call)
          expect(logger).to receive(:error).with(match(/refusing to materialize from a stale cache: API rate limit exceeded/))

          described_class.send(:run_materialization, report)

          expect(report[:aborted]).to eq('catalog_pull_failed')
          expect(report[:pull_errors]).to eq(['API rate limit exceeded'])
        end
      end

      # A pull can succeed while doing nothing: when Stripe returns no
      # matching products, Pull returns early without pruning, rebuilding, or
      # stamping the catalog, so the previous Redis plan cache survives
      # untouched. Treating that `success` as "cache is fresh" would
      # materialize every org from a stale catalog — the exact incident this
      # job exists to prevent.
      describe 'fail-closed abort when catalog pull succeeds but verifies nothing' do
        it 'aborts without materializing and logs at ERROR' do
          pull_result = make_pull_result(success: true, plans_synced: 0, catalog_verified: false)
          allow(Billing::Operations::Catalog::Pull).to receive(:call).and_return(pull_result)

          expect(Billing::Operations::MaterializePlans).not_to receive(:call)
          expect(logger).to receive(:error).with(match(/verified no plans/))

          described_class.send(:run_materialization, report)

          expect(report[:aborted]).to eq('catalog_pull_unverified')
          expect(report[:plans_synced]).to eq(0)
        end

        # Guards the opposite failure: the gate must not refuse a pull that
        # genuinely refreshed the catalog.
        it 'proceeds to materialize when the pull reports a verified catalog' do
          pull_result = make_pull_result(success: true, plans_synced: 2, catalog_verified: true)
          allow(Billing::Operations::Catalog::Pull).to receive(:call).and_return(pull_result)

          expect(Billing::Operations::MaterializePlans).to receive(:call)
            .with(include_memberships: true)
            .and_return(make_materialize_result(scanned: 2, succeeded: 2))

          described_class.send(:run_materialization, report)

          expect(report).not_to have_key(:aborted)
          expect(report[:plans_synced]).to eq(2)
        end
      end

      describe 'fail-closed abort when catalog pull raises' do
        it 'aborts without materializing and logs at ERROR' do
          allow(Billing::Operations::Catalog::Pull).to receive(:call)
            .and_raise(StandardError.new('Network unreachable'))

          expect(Billing::Operations::MaterializePlans).not_to receive(:call)
          expect(logger).to receive(:error).with(match(/refusing to materialize from a stale cache: StandardError - Network unreachable/))

          expect { described_class.send(:run_materialization, report) }.not_to raise_error

          expect(report[:aborted]).to eq('catalog_pull_raised')
          expect(report[:pull_errors]).to eq(['StandardError: Network unreachable'])
        end
      end

      describe 'success path' do
        let(:materialize_result) do
          make_materialize_result(
            scanned: 10,
            succeeded: 8,
            skipped_no_plan: 2,
            orgs_cascaded: 8,
            memberships_succeeded: 15
          )
        end

        before do
          allow(Billing::Operations::Catalog::Pull).to receive(:call)
            .and_return(make_pull_result(success: true, plans_synced: 5))
          allow(Billing::Operations::MaterializePlans).to receive(:call)
            .and_return(materialize_result)
        end

        it 'materializes with membership cascade enabled' do
          expect(Billing::Operations::MaterializePlans).to receive(:call)
            .with(include_memberships: true)
            .and_return(materialize_result)

          described_class.send(:run_materialization, report)
        end

        it 'copies result counts into the report' do
          described_class.send(:run_materialization, report)

          expect(report).to include(
            plans_synced: 5,
            scanned: 10,
            succeeded: 8,
            failed: 0,
            skipped_no_plan: 2,
            orgs_cascaded: 8,
            memberships_succeeded: 15,
            memberships_failed: 0
          )
        end

        it 'does not record errors or log at ERROR when nothing failed' do
          expect(logger).not_to receive(:error)

          described_class.send(:run_materialization, report)

          expect(report).not_to have_key(:errors)
        end
      end

      describe 'failure logging when orgs fail to materialize' do
        let(:org_errors) do
          [
            { org_extid: 'org_abc', reason: 'plan not found: plan_gone' },
            { org_extid: 'org_def', reason: 'write failed' },
          ]
        end

        before do
          allow(Billing::Operations::Catalog::Pull).to receive(:call)
            .and_return(make_pull_result(success: true, plans_synced: 3))
          allow(Billing::Operations::MaterializePlans).to receive(:call).and_return(
            make_materialize_result(
              scanned: 5,
              succeeded: 3,
              failed: 2,
              memberships_failed: 1,
              errors: org_errors
            )
          )
        end

        it 'records error details in the report' do
          described_class.send(:run_materialization, report)

          expect(report[:failed]).to eq(2)
          expect(report[:errors]).to eq(org_errors)
        end

        it 'logs failure count and error details at ERROR' do
          expect(logger).to receive(:error).with(
            match(/2 org\(s\) failed to materialize \(1 membership cascade failures\): .*org_abc/)
          )

          described_class.send(:run_materialization, report)
        end
      end
    end
  end
end
