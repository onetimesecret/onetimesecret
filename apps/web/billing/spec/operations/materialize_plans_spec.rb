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
  let(:fake_logger) { instance_double(SemanticLogger::Logger, info: nil, debug: nil, warn: nil, error: nil) }

  # Builds a membership double with the methods the operation calls inline
  # during the cascade. materialized_entitlements is read after a successful
  # materialize_for_role! to capture per-membership entitlement counts.
  def build_membership(objid:, role: 'member', entitlements_count: 4)
    membership = instance_double(Onetime::OrganizationMembership,
      objid: objid, role: role)
    allow(membership).to receive(:materialize_for_role!).with(org).and_return(true)
    allow(membership).to receive(:materialized_entitlements)
      .and_return(double('Set', size: entitlements_count))
    membership
  end

  let(:memberships) do
    [
      build_membership(objid: 'mem_aaa', role: 'owner', entitlements_count: 12),
      build_membership(objid: 'mem_bbb', role: 'admin', entitlements_count: 8),
      build_membership(objid: 'mem_ccc', role: 'member', entitlements_count: 4),
    ]
  end

  before do
    allow(plan).to receive(:entitlements).and_return(plan_entitlements)
    allow(Billing::Plan).to receive(:list_plans).and_return([plan])
    allow(iterator).to receive(:each_record).and_yield(org)

    allow(org).to receive(:materialize_entitlements_from_plan)
    allow(Onetime::OrganizationMembership).to receive(:active_for_org).with(org).and_return(memberships)

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

        memberships.each do |m|
          expect(m).not_to have_received(:materialize_for_role!)
        end
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
        expect(Onetime::OrganizationMembership).not_to have_received(:active_for_org)
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
      it 'cascades to every active membership and counts org as succeeded' do
        result = described_class.call(include_memberships: true, iterator: iterator)

        memberships.each do |m|
          expect(m).to have_received(:materialize_for_role!).with(org)
        end
        expect(result.succeeded).to eq(1)
        expect(result.failed).to eq(0)
        expect(result.orgs_cascaded).to eq(1)
        expect(result.memberships_succeeded).to eq(3)
        expect(result.memberships_failed).to eq(0)
      end

      it 'captures per-membership detail in the progress event for the verbose renderer' do
        events = []
        described_class.call(include_memberships: true, iterator: iterator) { |e| events << e }

        materialized = events.find { |e| e.event == :materialized }
        expect(materialized).not_to be_nil
        expect(materialized.cascade[:details].size).to eq(3)

        owner_detail = materialized.cascade[:details].find { |d| d[:objid] == 'mem_aaa' }
        expect(owner_detail).to include(
          role: 'owner',
          planid: 'test_plan_v1',
          entitlements_count: 12,
          status: :ok,
        )
      end

      it 'counts org as FAILED when any single membership raises (no masked partial success)' do
        allow(memberships[1]).to receive(:materialize_for_role!).and_raise(StandardError, 'membership boom')

        result = described_class.call(include_memberships: true, iterator: iterator)

        expect(result.succeeded).to eq(0)
        expect(result.failed).to eq(1)
        expect(result.memberships_succeeded).to eq(2)
        expect(result.memberships_failed).to eq(1)
        expect(result.errors.first[:org_extid]).to eq('org_test123')
        expect(result.errors.first[:reason]).to include('1/3 membership failures')
      end

      it 'records the failed-membership error string in the cascade details for audit' do
        allow(memberships[2]).to receive(:materialize_for_role!).and_raise(StandardError, 'membership boom')

        events = []
        described_class.call(include_memberships: true, iterator: iterator) { |e| events << e }

        failed_event = events.find { |e| e.event == :failed_cascade }
        expect(failed_event).not_to be_nil
        failed_detail = failed_event.cascade[:details].find { |d| d[:status] == :failed }
        expect(failed_detail[:error]).to include('membership boom')
      end

      it 'counts org as FAILED when active_for_org itself raises' do
        allow(Onetime::OrganizationMembership).to receive(:active_for_org)
          .and_raise(StandardError, 'cascade boom')

        result = described_class.call(include_memberships: true, iterator: iterator)

        expect(result.succeeded).to eq(0)
        expect(result.failed).to eq(1)
        expect(result.errors.first[:reason]).to include('cascade boom')
      end

      it 'does not cascade if the org write itself failed' do
        allow(org).to receive(:materialize_entitlements_from_plan).and_raise(StandardError, 'write failed')

        described_class.call(include_memberships: true, iterator: iterator)

        expect(Onetime::OrganizationMembership).not_to have_received(:active_for_org)
      end

      # materialize_for_role! returns false (does NOT raise) when the role has
      # no ROLE_ENTITLEMENTS template — e.g. a role removed from the catalog.
      # The operation must treat that no-op as a failure rather than counting
      # the org as a clean success while a membership silently stays
      # unmaterialized. The integration counterpart (a real unknown-role
      # membership) lives in the CLI integration spec.
      it 'counts org as FAILED when a membership materialize_for_role! returns false (no raise)' do
        allow(memberships[1]).to receive(:materialize_for_role!).and_return(false)

        result = described_class.call(include_memberships: true, iterator: iterator)

        expect(result.succeeded).to eq(0)
        expect(result.failed).to eq(1)
        expect(result.memberships_succeeded).to eq(2)
        expect(result.memberships_failed).to eq(1)
        expect(result.errors.first[:reason]).to include('1/3 membership failures')
      end

      it 'records the false-return reason in the cascade details for audit' do
        allow(memberships[2]).to receive(:materialize_for_role!).and_return(false)

        events = []
        described_class.call(include_memberships: true, iterator: iterator) { |e| events << e }

        failed_event  = events.find { |e| e.event == :failed_cascade }
        failed_detail = failed_event.cascade[:details].find { |d| d[:status] == :failed }
        expect(failed_detail[:error]).to include("returned false for role 'member'")
      end
    end

    context 'membership_loader seam' do
      # The cascade resolves memberships through an injectable loader (symmetric
      # to iterator:) so tests can supply the membership list directly instead
      # of stubbing OrganizationMembership.active_for_org's internal batch
      # primitive. Default behavior (active_for_org) is covered by the cascade
      # specs above.
      it 'uses the injected loader instead of active_for_org' do
        injected = [build_membership(objid: 'mem_zzz', role: 'member', entitlements_count: 7)]

        result = described_class.call(
          include_memberships: true,
          iterator: iterator,
          membership_loader: ->(_org) { injected },
        )

        expect(Onetime::OrganizationMembership).not_to have_received(:active_for_org)
        expect(injected.first).to have_received(:materialize_for_role!).with(org)
        expect(result.orgs_cascaded).to eq(1)
        expect(result.memberships_succeeded).to eq(1)
      end

      it 'counts org as FAILED when an injected membership raises' do
        boom = build_membership(objid: 'mem_boom', role: 'admin')
        allow(boom).to receive(:materialize_for_role!).and_raise(StandardError, 'injected boom')

        result = described_class.call(
          include_memberships: true,
          iterator: iterator,
          membership_loader: ->(_org) { [boom] },
        )

        expect(result.failed).to eq(1)
        expect(result.memberships_failed).to eq(1)
        expect(result.errors.first[:reason]).to include('1/1 membership failures')
      end

      # Defensive: the seam is documented for non-test callers, so a malformed
      # loader must not crash the cascade — a nil return and nil entries are
      # tolerated rather than raising NoMethodError mid-batch.
      it 'treats a loader returning nil as an empty cascade' do
        result = described_class.call(
          include_memberships: true,
          iterator: iterator,
          membership_loader: ->(_org) { nil },
        )

        expect(result.succeeded).to eq(1)
        expect(result.orgs_cascaded).to eq(1)
        expect(result.memberships_succeeded).to eq(0)
        expect(result.memberships_failed).to eq(0)
      end

      it 'skips nil entries in the loader result without crashing the cascade' do
        good = build_membership(objid: 'mem_good', role: 'member', entitlements_count: 4)

        result = described_class.call(
          include_memberships: true,
          iterator: iterator,
          membership_loader: ->(_org) { [nil, good, nil] },
        )

        expect(good).to have_received(:materialize_for_role!).with(org)
        expect(result.succeeded).to eq(1)
        expect(result.memberships_succeeded).to eq(1)
        expect(result.memberships_failed).to eq(0)
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

      it 'records a failure when the plan is not in the catalog' do
        allow(org).to receive(:planid).and_return('missing_plan')

        result = described_class.call(iterator: iterator)

        expect(result.failed).to eq(1)
        expect(result.errors.first[:reason]).to include("Plan 'missing_plan'")
      end
    end

    context 'idempotency (no "up-to-date" skip)' do
      # The earlier --stale / --force / skip-if-fresh behavior was removed:
      # the perf gain was minor and it caused cascades to be silently skipped
      # for up-to-date orgs when --include-memberships was set. Memberships
      # can drift independently of the org's entitlement set, so every
      # in-scope org is now processed unconditionally.

      it 'materializes an already-fresh org instead of skipping it' do
        allow(org).to receive(:entitlements_materialized?).and_return(true)
        allow(org).to receive(:entitlements_stale?).and_return(false)

        result = described_class.call(iterator: iterator)

        expect(org).to have_received(:materialize_entitlements_from_plan).with(plan)
        expect(result.succeeded).to eq(1)
      end

      it 'cascades to memberships of an already-fresh org when --include-memberships is set' do
        allow(org).to receive(:entitlements_materialized?).and_return(true)
        allow(org).to receive(:entitlements_stale?).and_return(false)

        result = described_class.call(include_memberships: true, iterator: iterator)

        memberships.each do |m|
          expect(m).to have_received(:materialize_for_role!).with(org)
        end
        expect(result.succeeded).to eq(1)
        expect(result.orgs_cascaded).to eq(1)
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

      it 'yields :failed_cascade when any membership materialization fails' do
        allow(memberships[0]).to receive(:materialize_for_role!).and_raise(StandardError, 'mem boom')
        allow(memberships[2]).to receive(:materialize_for_role!).and_raise(StandardError, 'mem boom')

        events = []
        described_class.call(include_memberships: true, iterator: iterator) { |e| events << e }

        expect(events.map(&:event)).to eq([:failed_cascade])
        expect(events.first.cascade[:success]).to eq(1)
        expect(events.first.cascade[:failed]).to eq(2)
        expect(events.first.cascade[:total]).to eq(3)
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

      it 'logs per-membership and aggregate cascade failures via SemanticLogger exception field' do
        memberships.each do |m|
          allow(m).to receive(:materialize_for_role!).and_raise(StandardError, 'mem boom')
        end

        described_class.call(include_memberships: true, iterator: iterator)

        # `exception:` routes through SemanticLogger's `log.exception` slot so
        # the production formatter's backtrace truncation (setup_loggers.rb)
        # applies. A raw `backtrace:` payload field bypasses that policy.
        expect(fake_logger).to have_received(:error).with(
          'Membership re-materialization failed',
          hash_including(:org_extid, :membership_objid, exception: kind_of(StandardError)),
        ).at_least(:once)
        expect(fake_logger).to have_received(:error).with(
          'Cascade had membership failures',
          hash_including(:org_extid, :planid, :memberships_failed),
        )
      end

      it 'logs cascade exceptions via SemanticLogger exception field (production-truncated)' do
        allow(Onetime::OrganizationMembership).to receive(:active_for_org)
          .and_raise(StandardError, 'kaboom')

        described_class.call(include_memberships: true, iterator: iterator)

        expect(fake_logger).to have_received(:error).with(
          'Cascade raised',
          hash_including(:org_extid, exception: kind_of(StandardError)),
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
