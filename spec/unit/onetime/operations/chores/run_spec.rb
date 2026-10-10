# spec/unit/onetime/operations/chores/run_spec.rb
#
# frozen_string_literal: true

# Onetime::Operations::Chores::Run (#4343): one allowlisted chore, on demand,
# inside an HTTP request.
#
# The dry-run examples are the safety property: housekeeping chores have no
# dry-run mode, so a dry run must never reach a chore body. They run against
# every allowlisted housekeeping chore with the record source replaced by a
# double that answers only `size`, so any attempt to iterate would raise.
#
# Live housekeeping examples go through the real HousekeepingJob.perform over
# an in-memory model; the entitlement examples go through the real
# EntitlementMaterializeJob.perform with Pull and MaterializePlans stubbed.

require 'spec_helper'
require 'onetime/operations/chores/run'

RSpec.describe Onetime::Operations::Chores::Run do
  let(:actor) { 'ur_colonel_public' }
  let(:catalog) { Onetime::Operations::Chores::Catalog }
  let(:chore_id) { 'housekeeping.organization.standardize_planid' }
  let(:run_id) { "chore.#{chore_id}" }

  # Answers exhausted? false for the first `checks` calls, true after.
  def budget_lasting(checks = Float::INFINITY, elapsed_ms: 42)
    calls = 0
    double('Budget', elapsed_ms: elapsed_ms).tap do |budget|
      allow(budget).to receive(:exhausted?) { (calls += 1) > checks }
    end
  end

  let(:budget) { budget_lasting }

  # An in-memory model with the surface HousekeepingJob.perform touches.
  # Each record's do_chore! logs its index, then returns `modifies` (or
  # raises when `raises`).
  def fake_model(count, modifies: true, raises: false)
    touched   = []
    records   = Array.new(count) do |index|
      double("record#{index}", identifier: "rec#{index}").tap do |record|
        allow(record).to receive(:do_chore!) do |_key|
          raise 'chore boom' if raises

          touched << index
          modifies
        end
      end
    end
    instances = Class.new do
      def initialize(records) = @records = records
      def each_record(batch_size:, &) = @records.each(&)
      def size = @records.size
    end.new(records)
    # A real Class: HousekeepingJob.perform resolves anything else by name.
    klass     = Class.new do
      class << self
        attr_accessor :instances
      end
      def self.name = 'Onetime::Organization'
      def self.chores = { standardize_planid: :registered }
    end
    klass.instances = instances
    allow(catalog).to receive(:model_class).and_return(klass)
    touched
  end

  def run(chore: chore_id, **opts)
    described_class.new(chore: chore, actor: actor, budget: budget, **opts).call
  end

  before do
    allow(Onetime.billing_config).to receive(:enabled?).and_return(false)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Onetime::ColonelAuditEvent).to receive(:record_access)
    allow(Onetime::Jobs::JobRun).to receive(:started)
    allow(Onetime::Jobs::JobRun).to receive(:finished)
  end

  describe '.new' do
    it 'refuses an unknown chore' do
      expect { described_class.new(chore: 'housekeeping.nope', actor: actor) }
        .to raise_error(ArgumentError, /unknown chore/)
    end

    it 'refuses the excluded vhost cleanup chore like any unknown id' do
      expect do
        described_class.new(chore: 'housekeeping.custom_domain.remove_orphaned_approximated_vhosts', actor: actor)
      end.to raise_error(ArgumentError, /unknown chore/)
    end

    it 'refuses the entitlement run when billing is off (it is not listed)' do
      expect { described_class.new(chore: 'entitlement_materialize', actor: actor) }
        .to raise_error(ArgumentError, /unknown chore/)
    end
  end

  describe 'limit' do
    before { fake_model(0) }

    it 'defaults to 100' do
      expect(described_class::DEFAULT_LIMIT).to eq(100)
      expect(run.limit).to eq(100)
      expect(run(limit: nil).limit).to eq(100)
    end

    it 'clamps to 1..MAX_LIMIT' do
      expect(described_class::MAX_LIMIT).to eq(1_000)
      expect(run(limit: 0).limit).to eq(1)
      expect(run(limit: -5).limit).to eq(1)
      expect(run(limit: 50_000).limit).to eq(1_000)
      expect(run(limit: '25').limit).to eq(25)
    end
  end

  it 'starts a fresh budget of BUDGET_SECONDS (at most 10 s) when none is given' do
    fake_model(0)
    expect(described_class::BUDGET_SECONDS).to be <= 10
    expect(Onetime::Operations::Chores::Budget).to receive(:new).with(described_class::BUDGET_SECONDS).and_call_original

    described_class.new(chore: chore_id, actor: actor).call
  end

  # ---------------------------------------------------------------------------
  # Dry run of a housekeeping chore: never executes it
  # ---------------------------------------------------------------------------
  describe 'housekeeping dry run' do
    let(:housekeeping_entries) { catalog.all.select(&:housekeeping?) }

    before do
      housekeeping_entries.map(&:model).uniq.each do |model|
        # Answers `size` and nothing else: iterating would raise.
        allow(Object.const_get(model)).to receive(:instances).and_return(double('instances', size: 250))
      end
    end

    it 'covers every allowlisted housekeeping chore' do
      expect(housekeeping_entries.size).to eq(7)
    end

    it 'never runs the chore, for any allowlisted chore' do
      allow(Onetime::Jobs::Scheduled::HousekeepingJob).to receive(:perform)
      handlers = housekeeping_entries.map do |entry|
        Object.const_get(entry.model).chores.fetch(entry.chore.to_sym).tap do |handler|
          allow(handler).to receive(:call)
        end
      end

      housekeeping_entries.each { |entry| run(chore: entry.id, dry_run: true) }

      expect(Onetime::Jobs::Scheduled::HousekeepingJob).not_to have_received(:perform)
      handlers.each { |handler| expect(handler).not_to have_received(:call) }
    end

    it 'reports what a run would scan, and that the chore was not evaluated' do
      result = run(dry_run: true)

      expect(result).to have_attributes(
        status: :dry_run, chore: chore_id, kind: 'housekeeping', dry_run: true, limit: 100,
        capped: false, budget_exhausted: false, duration_ms: 42,
      )
      expect(result.report).to eq('would_scan' => 100, 'total' => 250, 'dry_run_supported' => false)
    end

    it 'records ONE preview observation and nothing on the operator trail' do
      run(dry_run: true, limit: 300)

      expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
        actor: actor,
        verb: 'chore.run',
        target: chore_id,
        result: 'preview',
        detail: { limit: 300, would_scan: 250, total: 250, dry_run: true },
      )
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end

    it 'writes no run record' do
      run(dry_run: true)

      expect(Onetime::Jobs::JobRun).not_to have_received(:started)
      expect(Onetime::Jobs::JobRun).not_to have_received(:finished)
    end
  end

  # ---------------------------------------------------------------------------
  # Live housekeeping run
  # ---------------------------------------------------------------------------
  describe 'housekeeping live run' do
    it 'runs the one chore through HousekeepingJob.perform with the limit and budget' do
      touched = fake_model(5)
      expect(Onetime::Jobs::Scheduled::HousekeepingJob).to receive(:perform)
        .with(anything, 'standardize_planid', limit: 100, budget: budget).and_call_original

      result = run

      expect(touched).to eq([0, 1, 2, 3, 4])
      expect(result).to have_attributes(
        status: :success, dry_run: false, limit: 100, capped: false, budget_exhausted: false, duration_ms: 42,
      )
      expect(result.report).to eq(
        'model' => 'Onetime::Organization', 'scanned' => 5, 'modified' => 5, 'errors' => 0,
      )
    end

    it 'records the applied run, fail-closed, with counts only' do
      fake_model(5)
      run

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'chore.run',
        target: chore_id,
        result: :success,
        detail: {
          dry_run: false, limit: 100, capped: false, budget_exhausted: false, status: 'success',
          scanned: 5, modified: 5, errors: 0,
        },
        fail_closed: true,
      )
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record_access)
    end

    it 'writes the run record: started, then success with the duration' do
      fake_model(2)
      run

      expect(Onetime::Jobs::JobRun).to have_received(:started).with(run_id).ordered
      expect(Onetime::Jobs::JobRun).to have_received(:finished)
        .with(run_id, status: 'success', duration_ms: 42, error: nil).ordered
    end

    it 'stops at the limit and reports capped' do
      touched = fake_model(5)
      result  = run(limit: 3)

      expect(touched).to eq([0, 1, 2])
      expect(result.capped).to be true
      expect(result.report['scanned']).to eq(3)
    end

    it 'stops between records when the budget runs out and reports partial counts' do
      touched = fake_model(5)
      result  = run(budget: budget_lasting(2))

      expect(touched).to eq([0, 1])
      expect(result).to have_attributes(status: :success, capped: false, budget_exhausted: true)
      expect(result.report).to include('scanned' => 2, 'modified' => 2)
      expect(Onetime::ColonelAuditEvent).to have_received(:record)
        .with(hash_including(detail: hash_including(budget_exhausted: true, scanned: 2)))
    end

    it 'records a run that modified nothing as a no-change attempt, not fail-closed' do
      fake_model(3, modifies: false)
      run

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'chore.run',
        target: chore_id,
        result: :success,
        detail: {
          dry_run: false, limit: 100, capped: false, budget_exhausted: false, status: 'success',
          scanned: 3, modified: 0, errors: 0, outcome: 'no_change',
        },
      )
    end

    it 'records per-record chore errors as an applied run (not a no-change)' do
      fake_model(2, raises: true)
      allow(OT).to receive(:le)

      result = run

      expect(result.report).to include('modified' => 0, 'errors' => 2)
      expect(Onetime::ColonelAuditEvent).to have_received(:record)
        .with(hash_including(result: :success, fail_closed: true, detail: hash_including(errors: 2)))
    end

    it 'records a raise as a failure, marks the run record error, and re-raises' do
      fake_model(1)
      allow(Onetime::Jobs::Scheduled::HousekeepingJob).to receive(:perform).and_raise(RuntimeError, 'redis gone')

      expect { run }.to raise_error(RuntimeError, 'redis gone')

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'chore.run',
        target: chore_id,
        result: :failure,
        detail: { dry_run: false, limit: 100, error: 'RuntimeError', message: 'redis gone' },
      )
      expect(Onetime::Jobs::JobRun).to have_received(:finished)
        .with(run_id, status: 'error', duration_ms: 42, error: 'RuntimeError: redis gone')
    end
  end

  # ---------------------------------------------------------------------------
  # Entitlement materialization (billing)
  # ---------------------------------------------------------------------------
  describe 'entitlement run' do
    let(:chore_id) { 'entitlement_materialize' }
    let(:job) { Onetime::Jobs::Scheduled::Maintenance::EntitlementMaterializeJob }
    let(:pull) { Billing::Operations::Catalog::Pull }
    let(:materialize) { Billing::Operations::MaterializePlans }
    let(:scheduler_logger) { double('Logger', info: nil, debug: nil, warn: nil, error: nil) }

    def materialize_result(**overrides)
      Billing::Operations::MaterializePlansResult.new(
        scanned: 0, succeeded: 0, failed: 0, skipped_no_plan: 0, skipped_plan_filter: 0,
        memberships_succeeded: 0, memberships_failed: 0, orgs_cascaded: 0, errors: [], **overrides
      )
    end

    before do
      allow(Onetime.billing_config).to receive(:enabled?).and_return(true)
      allow(Onetime.billing_config).to receive(:stripe_key).and_return('sk_test_123')
      allow(job).to receive(:scheduler_logger).and_return(scheduler_logger)
    end

    describe 'dry run' do
      before do
        allow(pull).to receive(:call)
        allow(job).to receive(:perform)
        allow(materialize).to receive(:call).and_return(
          materialize_result(scanned: 100, succeeded: 90, skipped_no_plan: 8, failed: 2),
        )
      end

      it 'evaluates orgs with MaterializePlans in dry-run mode, bounded' do
        result = run(dry_run: true)

        expect(materialize).to have_received(:call)
          .with(include_memberships: true, dry_run: true, limit: 100, budget: budget)
        expect(result).to have_attributes(status: :dry_run, kind: 'billing', capped: true, budget_exhausted: false)
        expect(result.report).to eq(
          'scanned' => 100, 'would_materialize' => 90, 'skipped_no_plan' => 8, 'plan_not_found' => 2,
          'catalog_pulled' => false,
        )
      end

      it 'never pulls the catalog or takes the live path' do
        run(dry_run: true)

        expect(pull).not_to have_received(:call)
        expect(job).not_to have_received(:perform)
        expect(Onetime::Jobs::JobRun).not_to have_received(:started)
      end

      it 'records ONE preview observation' do
        run(dry_run: true)

        expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
          actor: actor, verb: 'chore.run', target: 'entitlement_materialize', result: 'preview',
          detail: { limit: 100, scanned: 100, would_materialize: 90, skipped_no_plan: 8, dry_run: true },
        )
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      end
    end

    describe 'live run' do
      it 'goes through the job: catalog pull first, then a bounded materialize' do
        expect(job).to receive(:perform).with({}, limit: 100, budget: budget).and_call_original
        expect(pull).to receive(:call).ordered
          .and_return(pull::Result.new(success: true, plans_synced: 3, catalog_verified: true))
        expect(materialize).to receive(:call).ordered
          .with(include_memberships: true, limit: 100, budget: budget)
          .and_return(materialize_result(scanned: 40, succeeded: 39, failed: 1,
            errors: [{ org_extid: 'org_x', reason: 'boom' }]))

        result = run

        expect(result).to have_attributes(status: :success, capped: false, budget_exhausted: false)
        expect(result.report).to include(
          'plans_synced' => 3, 'scanned' => 40, 'succeeded' => 39, 'failed' => 1,
          'errors' => [{ 'org_extid' => 'org_x', 'reason' => 'boom' }],
        )
      end

      it 'audits counts, fail-closed, and never the per-org ids' do
        allow(pull).to receive(:call).and_return(pull::Result.new(success: true, plans_synced: 3, catalog_verified: true))
        allow(materialize).to receive(:call).and_return(
          materialize_result(scanned: 40, succeeded: 39, failed: 1, errors: [{ org_extid: 'org_x', reason: 'boom' }]),
        )

        run

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          actor: actor,
          verb: 'chore.run',
          target: 'entitlement_materialize',
          result: :success,
          detail: {
            dry_run: false, limit: 100, capped: false, budget_exhausted: false, status: 'success',
            plans_synced: 3, scanned: 40, succeeded: 39, failed: 1, skipped_no_plan: 0,
          },
          fail_closed: true,
        )
      end

      it 'reports a budget the materialize ran out of' do
        allow(pull).to receive(:call).and_return(pull::Result.new(success: true, plans_synced: 3, catalog_verified: true))
        allow(materialize).to receive(:call)
          .and_return(materialize_result(scanned: 7, succeeded: 7, budget_exhausted: true))

        expect(run).to have_attributes(status: :success, budget_exhausted: true, capped: false)
      end

      it 'maps a refused pull to aborted: no materialize, a failure attempt, an error run record' do
        allow(pull).to receive(:call).and_return(pull::Result.new(success: false, errors: ['rate limited']))
        allow(materialize).to receive(:call)

        result = run

        expect(materialize).not_to have_received(:call)
        expect(result.status).to eq(:aborted)
        expect(result.report).to include('aborted' => 'catalog_pull_failed', 'pull_errors' => ['rate limited'])
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          actor: actor,
          verb: 'chore.run',
          target: 'entitlement_materialize',
          result: :failure,
          detail: {
            dry_run: false, limit: 100, capped: false, budget_exhausted: false, status: 'aborted',
            aborted: 'catalog_pull_failed', outcome: 'aborted',
          },
        )
        expect(Onetime::Jobs::JobRun).to have_received(:finished)
          .with('chore.entitlement_materialize', status: 'error', duration_ms: 42, error: 'aborted: catalog_pull_failed')
      end

      it 'maps a missing Stripe key to skipped: a no-change attempt and a skipped run record' do
        allow(Onetime.billing_config).to receive(:stripe_key).and_return(nil)
        allow(pull).to receive(:call)

        result = run

        expect(pull).not_to have_received(:call)
        expect(result.status).to eq(:skipped)
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(
            result: :success,
            detail: hash_including(status: 'skipped', skipped: 'no_stripe_key', outcome: 'no_change'),
          ),
        )
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record).with(hash_including(fail_closed: true))
        expect(Onetime::Jobs::JobRun).to have_received(:finished)
          .with('chore.entitlement_materialize', status: 'skipped', duration_ms: 42, error: nil)
      end
    end
  end
end
