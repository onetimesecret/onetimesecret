# spec/unit/onetime/operations/chores/catalog_spec.rb
#
# frozen_string_literal: true

# Onetime::Operations::Chores::Catalog (#4343): the allowlist of chores the
# colonel console may run.
#
# The drift examples are the point of this file. A chore registered on a model
# must be either allowlisted or excluded with a reason, so a new chore cannot
# reach the console without someone deciding it is safe to trigger from a
# browser; and an allowlisted chore that is no longer registered must be
# removed from the list rather than silently disappear.

require 'spec_helper'
require 'onetime/operations/chores/catalog'
require 'onetime/operations/chores/budget'

RSpec.describe Onetime::Operations::Chores::Catalog do
  let(:housekeeping_job) { Onetime::Jobs::Scheduled::HousekeepingJob }

  # Every housekeeping chore id the running app registers, by the catalog's
  # own id rule. Two sources: the models the nightly sweep runs, and every
  # Onetime Familia model with chores at all (the config models register one
  # but sit outside the sweep unless configured).
  def registered_ids(models)
    models.flat_map do |klass|
      klass.chores.keys.map { |chore| described_class.housekeeping_id(klass, chore) }
    end
  end

  let(:all_chore_models) do
    Familia.members.select do |klass|
      klass.name.to_s.start_with?('Onetime::') && klass.respond_to?(:chores) && klass.chores.any?
    end
  end

  let(:decided_ids) { described_class::HOUSEKEEPING.keys + described_class::EXCLUDED.keys }

  before { allow(Onetime.billing_config).to receive(:enabled?).and_return(false) }

  describe 'allowlist drift' do
    it 'finds the chores the sweep runs (guards against an empty discovery)' do
      expect(registered_ids(housekeeping_job.models_with_chores)).not_to be_empty
    end

    it 'decides every chore HousekeepingJob.models_with_chores registers' do
      undecided = registered_ids(housekeeping_job.models_with_chores) - decided_ids

      expect(undecided).to be_empty,
        "chores neither allowlisted nor excluded: #{undecided.inspect}. Add each to " \
        'Catalog::HOUSEKEEPING (runnable from the console) or Catalog::EXCLUDED (with the reason).'
    end

    it 'decides every chore registered on any Onetime model, swept or not' do
      undecided = registered_ids(all_chore_models) - decided_ids

      expect(undecided).to be_empty, "chores neither allowlisted nor excluded: #{undecided.inspect}"
    end

    it 'allowlists only chores that are still registered on their model' do
      stale = described_class::HOUSEKEEPING.reject do |_id, (model, chore)|
        klass = Object.const_get(model)
        klass.respond_to?(:chores) && klass.chores.key?(chore.to_sym)
      end

      expect(stale.keys).to be_empty, "allowlisted chores no longer registered: #{stale.keys.inspect}"
    end

    it 'excludes only ids that exist (a stale exclusion hides nothing)' do
      stale = described_class::EXCLUDED.keys - registered_ids(all_chore_models)

      expect(stale).to be_empty
    end

    it 'writes each allowlist key as the id its model and chore derive' do
      described_class::HOUSEKEEPING.each do |id, (model, chore)|
        expect(described_class.housekeeping_id(model, chore)).to eq(id)
      end
    end

    it 'never both allowlists and excludes an id' do
      expect(described_class::HOUSEKEEPING.keys & described_class::EXCLUDED.keys).to be_empty
    end

    it 'gives every exclusion a reason' do
      expect(described_class::EXCLUDED.values).to all(satisfy { |reason| reason.to_s.strip.length > 10 })
    end
  end

  describe '.all' do
    it 'lists the seven allowlisted housekeeping chores, one id per chore' do
      expect(described_class.all.map(&:id)).to eq(
        %w[
          housekeeping.organization.materialize_standalone_entitlements
          housekeeping.organization.ensure_member_through_models
          housekeeping.organization.standardize_owner_id
          housekeeping.organization.standardize_planid
          housekeeping.custom_domain.migrate_ownership_verified
          housekeeping.custom_domain.migrate_incoming_secrets_to_config
          housekeeping.customer.reserialize_fields
        ],
      )
    end

    it 'describes a housekeeping chore with its single chore name and CLI equivalent' do
      entry = described_class.find('housekeeping.organization.standardize_planid')

      expect(entry.to_h).to eq(
        id: 'housekeeping.organization.standardize_planid',
        kind: 'housekeeping',
        model: 'Onetime::Organization',
        chore: 'standardize_planid',
        supports_dry_run: false,
        cli: 'bin/ots housekeeping run Onetime::Organization standardize_planid',
      )
      expect(entry.chores).to eq(['standardize_planid'])
      expect(entry.run_id).to eq('chore.housekeeping.organization.standardize_planid')
    end

    it 'adds the entitlement run, the one chore with a dry run, only when billing is enabled' do
      expect(described_class.valid?('entitlement_materialize')).to be false

      allow(Onetime.billing_config).to receive(:enabled?).and_return(true)
      entry = described_class.find('entitlement_materialize')

      expect(entry).to have_attributes(
        kind: 'billing', model: 'Onetime::Organization', chore: nil, supports_dry_run: true,
        cli: 'bin/ots billing catalog pull && bin/ots billing plans materialize --all --include-memberships --run',
      )
      expect(entry.chores).to eq([])
      expect(described_class.all.last).to eq(entry)
    end

    it 'follows the sweep: a model the sweep does not run lists no chores' do
      allow(housekeeping_job).to receive(:models_with_chores).and_return([Onetime::Customer])

      expect(described_class.all.map(&:id)).to eq(%w[housekeeping.customer.reserialize_fields])
    end

    it 'drops an allowlisted chore its model no longer registers instead of failing' do
      shrunk = Class.new do
        def self.name = 'Onetime::Customer'
        def self.chores = {}
      end
      allow(housekeeping_job).to receive(:models_with_chores).and_return([shrunk])

      expect(described_class.all).to be_empty
    end
  end

  describe 'the vhost cleanup chore (CLI-only)' do
    let(:id) { 'housekeeping.custom_domain.remove_orphaned_approximated_vhosts' }

    it 'is registered, so the exclusion is doing work' do
      expect(Onetime::CustomDomain.chores).to have_key(:remove_orphaned_approximated_vhosts)
    end

    it 'is excluded with its reason and never listed' do
      expect(described_class::EXCLUDED.fetch(id)).to include('irreversible')
      expect(described_class.all.map(&:id)).not_to include(id)
      expect(described_class.find(id)).to be_nil
      expect(described_class.valid?(id)).to be false
    end
  end

  it 'rejects unknown ids' do
    expect(described_class.find('housekeeping.organization')).to be_nil
    expect(described_class.valid?('')).to be false
  end

  # The chore implementations live in Onetime::Chores; this namespace must not
  # shadow them.
  it 'leaves Onetime::Chores (the chore implementations) a separate namespace' do
    expect(Onetime::Operations::Chores).not_to equal(Onetime::Chores)
    expect(Onetime::Chores::StandardizePlanid::CANONICAL_PLANIDS).to include('free_v1')
  end
end

RSpec.describe Onetime::Operations::Chores::Budget do
  it 'is exhausted once the clock reaches the deadline, and stays exhausted' do
    ticks  = [100.0, 104.0, 110.0, 105.0]
    budget = described_class.new(10, clock: -> { ticks.shift })

    expect(budget.exhausted?).to be false # 104
    expect(budget.exhausted?).to be true  # 110
    expect(budget.exhausted?).to be true  # sticky; the clock is not read again
    expect(budget.elapsed_ms).to eq(5000)
  end

  it 'gives a loop that starts late at least min_loop_seconds from its first check' do
    now    = 100.0
    budget = described_class.new(8, min_loop_seconds: 3, clock: -> { now })

    now = 109.0 # a 9 s uninterruptible step before the loop
    expect(budget.exhausted?).to be false # first check: the loop now has until 112
    now = 111.5
    expect(budget.exhausted?).to be false
    now = 112.0
    expect(budget.exhausted?).to be true
  end

  it 'leaves a loop that starts right away on the full allowance' do
    now    = 100.0
    budget = described_class.new(8, min_loop_seconds: 3, clock: -> { now })

    expect(budget.exhausted?).to be false # first check at 100: floor ends at 103, allowance at 108
    now = 107.9
    expect(budget.exhausted?).to be false
    now = 108.0
    expect(budget.exhausted?).to be true
  end
end
