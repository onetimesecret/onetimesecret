# apps/web/billing/spec/operations/materialize_plans_spec.rb
#
# frozen_string_literal: true

# Specs for Billing::Operations::MaterializePlans.
#
# The operation iterates organizations, materializes entitlements from plan
# definitions, and optionally cascades to active memberships. Tests focus on
# the accounting invariants — particularly that cascade failures count the
# org as FAILED rather than masking partial success.
#
# Run: pnpm run test:rspec apps/web/billing/spec/operations/materialize_plans_spec.rb

require_relative '../support/billing_spec_helper'
require_relative '../../operations/materialize_plans'

RSpec.describe Billing::Operations::MaterializePlans, :billing_cli do
  let(:org) { instance_double(Onetime::Organization, extid: 'org_test123', planid: 'test_plan_v1') }
  let(:plan) { instance_double(Billing::Plan, plan_id: 'test_plan_v1') }
  let(:plan_entitlements) { double('entitlements', size: 5) }
  let(:iterator) { double('iterator') }
  let(:fake_logger) { instance_double(Logger, info: nil, debug: nil, warn: nil, error: nil) }

  before do
    allow(plan).to receive(:entitlements).and_return(plan_entitlements)
    allow(Billing::Plan).to receive(:list_plans).and_return([plan])
    allow(iterator).to receive(:each_record).and_yield(org)

    # Default org state: not yet materialized, will be processed.
    allow(org).to receive(:entitlements_materialized?).and_return(false)
    allow(org).to receive(:entitlements_stale?).and_return(false)
    allow(org).to receive(:materialize_entitlements_from_plan)
    allow(org).to receive(:rematerialize_all_memberships!)
      .and_return({ success: 3, failed: 0, total: 3 })

    # Route the operation's logger to a controllable fake so tests can
    # assert on log calls without depending on the live billing category.
    allow(Onetime).to receive(:billing_logger).and_return(fake_logger)
  end

  describe '.call' do
    context 'dry-run mode' do
      it 'returns a would-succeed result without writing' do
        result = described_class.call(dry_run: true, iterator: iterator)

        expect(org).not_to have_received(:materialize_entitlements_from_plan)
        expect(result.scanned).to eq(1)
        expect(result.succeeded).to eq(1)
        expect(result.failed).to eq(0)
      end

      it 'does not cascade in dry-run even when --include-memberships is set' do
        described_class.call(dry_run: true, include_memberships: true, iterator: iterator)

        expect(org).not_to have_received(:rematerialize_all_memberships!)
      end

      it 'emits :would_materialize via the progress block' do
        events = []
        described_class.call(dry_run: true, iterator: iterator) { |e| events << e }

        expect(events.map(&:event)).to eq([:would_materialize])
        expect(events.first.entitlements_count).to eq(5)
      end
    end

    context 'write mode without cascade' do
      it 'materializes the org and counts as succeeded' do
        result = described_class.call(iterator: iterator)

        expect(org).to have_received(:materialize_entitlements_from_plan).with(plan)
        expect(org).not_to have_received(:rematerialize_all_memberships!)
        expect(result.succeeded).to eq(1)
        expect(result.failed).to eq(0)
        expect(result.orgs_cascaded).to eq(0)
      end

      it 'counts an org-write exception as failed and captures the error' do
        allow(org).to receive(:materialize_entitlements_from_plan).and_raise(StandardError, 'redis down')

        result = described_class.call(iterator: iterator)

        expect(result.succeeded).to eq(0)
        expect(result.failed).to eq(1)
        expect(result.errors.first[:org_extid]).to eq('org_test123')
        expect(result.errors.first[:reason]).to include('redis down')
      end
    end

    context 'write mode with --include-memberships' do
      it 'cascades and counts org as succeeded when all memberships materialize' do
        result = described_class.call(include_memberships: true, iterator: iterator)

        expect(org).to have_received(:rematerialize_all_memberships!)
        expect(result.succeeded).to eq(1)
        expect(result.failed).to eq(0)
        expect(result.orgs_cascaded).to eq(1)
        expect(result.memberships_succeeded).to eq(3)
        expect(result.memberships_failed).to eq(0)
      end

      it 'counts org as FAILED when any memberships fail (no masked partial success)' do
        allow(org).to receive(:rematerialize_all_memberships!)
          .and_return({ success: 2, failed: 1, total: 3 })

        result = described_class.call(include_memberships: true, iterator: iterator)

        expect(result.succeeded).to eq(0)
        expect(result.failed).to eq(1)
        expect(result.memberships_succeeded).to eq(2)
        expect(result.memberships_failed).to eq(1)
        expect(result.errors.first[:org_extid]).to eq('org_test123')
        expect(result.errors.first[:reason]).to include('1/3 membership failures')
      end

      it 'counts org as FAILED when cascade raises' do
        allow(org).to receive(:rematerialize_all_memberships!).and_raise(StandardError, 'cascade boom')

        result = described_class.call(include_memberships: true, iterator: iterator)

        expect(result.succeeded).to eq(0)
        expect(result.failed).to eq(1)
        expect(result.errors.first[:reason]).to include('cascade boom')
      end

      it 'does not cascade if the org write itself failed' do
        allow(org).to receive(:materialize_entitlements_from_plan).and_raise(StandardError, 'write failed')

        described_class.call(include_memberships: true, iterator: iterator)

        expect(org).not_to have_received(:rematerialize_all_memberships!)
      end
    end

    context 'skip conditions' do
      it 'skips orgs with no planid' do
        allow(org).to receive(:planid).and_return('')

        result = described_class.call(iterator: iterator)

        expect(result.skipped_no_plan).to eq(1)
        expect(result.succeeded).to eq(0)
        expect(org).not_to have_received(:materialize_entitlements_from_plan)
      end

      it 'skips orgs whose plan does not match --plan filter' do
        allow(org).to receive(:planid).and_return('other_plan')

        result = described_class.call(plan_filter: 'test_plan_v1', iterator: iterator)

        expect(result.skipped_plan_filter).to eq(1)
        expect(result.succeeded).to eq(0)
      end

      it 'skips fresh orgs by default and does NOT cascade' do
        allow(org).to receive(:entitlements_materialized?).and_return(true)
        allow(org).to receive(:entitlements_stale?).and_return(false)

        result = described_class.call(include_memberships: true, iterator: iterator)

        expect(result.skipped_up_to_date).to eq(1)
        expect(org).not_to have_received(:materialize_entitlements_from_plan)
        expect(org).not_to have_received(:rematerialize_all_memberships!)
      end

      it '--force overrides the up-to-date skip and still cascades' do
        allow(org).to receive(:entitlements_materialized?).and_return(true)
        allow(org).to receive(:entitlements_stale?).and_return(false)

        result = described_class.call(force: true, include_memberships: true, iterator: iterator)

        expect(org).to have_received(:materialize_entitlements_from_plan).with(plan)
        expect(org).to have_received(:rematerialize_all_memberships!)
        expect(result.succeeded).to eq(1)
      end

      it 'records a failure when the plan is not in the catalog' do
        allow(org).to receive(:planid).and_return('missing_plan')

        result = described_class.call(iterator: iterator)

        expect(result.failed).to eq(1)
        expect(result.errors.first[:reason]).to include("Plan 'missing_plan'")
      end
    end

    context 'progress streaming' do
      it 'yields one event per scanned org' do
        events = []
        described_class.call(iterator: iterator) { |e| events << e }

        expect(events.size).to eq(1)
        expect(events.first.event).to eq(:materialized)
        expect(events.first.org_extid).to eq('org_test123')
      end

      it 'yields :failed_cascade when cascade reports failures' do
        allow(org).to receive(:rematerialize_all_memberships!)
          .and_return({ success: 1, failed: 2, total: 3 })

        events = []
        described_class.call(include_memberships: true, iterator: iterator) { |e| events << e }

        expect(events.map(&:event)).to eq([:failed_cascade])
        expect(events.first.cascade).to eq({ success: 1, failed: 2, total: 3 })
      end
    end

    context 'logging' do
      it 'logs start and end lifecycle milestones at info level via the billing logger' do
        described_class.call(iterator: iterator)

        expect(fake_logger).to have_received(:info).with(
          'Materializing org entitlements from plan catalog',
          hash_including(:dry_run, :include_memberships),
        )
        expect(fake_logger).to have_received(:info).with(
          'Materialization complete',
          hash_including(:scanned, :succeeded, :failed),
        )
      end

      it 'logs cascade failures at error level (paired with debug backtrace path)' do
        allow(org).to receive(:rematerialize_all_memberships!)
          .and_return({ success: 0, failed: 3, total: 3 })

        described_class.call(include_memberships: true, iterator: iterator)

        expect(fake_logger).to have_received(:error).with(
          'Cascade had membership failures',
          hash_including(:org_extid, :planid, :memberships_failed),
        )
      end

      it 'logs cascade exceptions at error level and emits a debug backtrace line' do
        allow(org).to receive(:rematerialize_all_memberships!).and_raise(StandardError, 'kaboom')

        described_class.call(include_memberships: true, iterator: iterator)

        expect(fake_logger).to have_received(:error).with(
          'Cascade raised',
          hash_including(:org_extid, :message),
        )
        expect(fake_logger).to have_received(:debug).with(
          'Cascade raised (backtrace)',
          hash_including(:org_extid, :backtrace),
        )
      end

      it 'logs plan-not-found at warn level' do
        allow(org).to receive(:planid).and_return('missing_plan')

        described_class.call(iterator: iterator)

        expect(fake_logger).to have_received(:warn).with(
          'Plan not found in catalog or config',
          hash_including(:org_extid, :planid),
        )
      end

      it 'logs routine per-org progress at debug level (not info)' do
        described_class.call(iterator: iterator)

        expect(fake_logger).to have_received(:debug).with(
          'Materialized org entitlements',
          hash_including(:org_extid, :planid, :entitlements_count),
        )
      end
    end
  end
end
