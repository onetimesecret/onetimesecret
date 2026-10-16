# spec/cli/domains_resolve_collisions_command_spec.rb
#
# frozen_string_literal: true

# `bin/ots domains resolve-collisions` is a thin adapter over
# Onetime::Operations::Domains::CollisionResolution. The op is stubbed with
# plans and results built from its own Data classes; under test here is the
# adapter: plan by default, --write, the plan-file loading and refusals around
# --apply, the exit status and the JSON shape. The op against a real datastore
# is covered by spec/unit/onetime/operations/domains/collision_resolution_spec.rb.

require_relative 'cli_spec_helper'
require 'tmpdir'

RSpec.describe 'Domains resolve-collisions command', type: :cli do
  let(:op_class) { Onetime::Operations::Domains::CollisionResolution }
  let(:op) { instance_double(op_class) }

  def record(id, **over)
    defaults = {
      domain_id: id,
      extid: "cd#{id}",
      display_domain: 'pair.example',
      org_id: "org-#{id}",
      org_extid: "on#{id}",
      org_name: 'Org',
      org_state: :active,
      served: false,
      verification_state: :pending,
      ownership_verified: false,
      verified_by_override: false,
      verified_confirmed_at: nil,
      receipts: 0,
      configs: [],
      all_configs: [],
      brand: false,
      vhost: false,
      created: 1_700_000_000,
    }
    op_class::Record.new(**defaults, **over)
  end

  def group(ascii_name, decision: :auto, rule: :dns_proof, keep: 'cdb', remove: ['cda'], notes: [])
    op_class::Group.new(
      ascii_name: ascii_name,
      decision: decision,
      rule: rule,
      keep: keep,
      remove: remove,
      notes: notes,
      records: [record('a', served: true), record('b', verified_confirmed_at: 1_700_000_100)],
      approved: false,
      skip: false,
    )
  end

  def plan(*groups)
    op_class::Plan.new(generated_at: '2026-10-16T00:00:00Z', rule_version: op_class::Rule::VERSION, strategy: 'passthrough', groups: groups)
  end

  def apply_result(status, dry_run: false, reason: nil)
    op_class::ApplyResult.new(
      dry_run: dry_run,
      strategy: 'passthrough',
      outcomes: [
        op_class::Outcome.new(
          ascii_name: 'pair.example',
          status: status,
          reason: reason,
          keep: 'cdb',
          removals: if status == :skipped
[]
else
[op_class::Removal.new(ref: 'cda', display_domain: 'pair.example', status: dry_run ? :planned : :removed, detail: nil)]
end,
          index_claim: status == :applied ? :created : nil,
          verify_state: nil,
          errors: [],
        ),
      ],
    )
  end

  def write_plan(dir, plan)
    path = File.join(dir, 'plan.json')
    File.write(path, plan.to_json)
    path
  end

  before do
    allow(op_class).to receive(:new).and_return(op)
  end

  around do |example|
    Dir.mktmpdir('resolve-collisions') do |dir|
      @dir = dir
      example.run
    end
  end

  describe 'plan (default)' do
    it 'prints the decided groups and exits 0 when no group is manual' do
      allow(op).to receive(:plan).and_return(plan(group('pair.example', notes: ['cda answers for the name today; after the removal cdb does'])))

      output = run_cli_command_quietly('domains', 'resolve-collisions')

      expect(output[:stdout]).to include('pair.example  auto: dns_proof', 'KEEP   cdb', 'REMOVE cda', 'served', 'shadow', 'note: cda answers')
      expect(output[:stdout]).to include('resolve-collisions --apply --plan')
      expect(last_exit_code).to eq(0)
    end

    it 'exits 1 while a manual group is undecided, and writes the plan with --write' do
      allow(op).to receive(:plan).and_return(plan(group('pair.example', decision: :manual, rule: :manual_several_in_use, keep: nil, remove: [])))
      path = File.join(@dir, 'out.json')

      output = run_cli_command_quietly('domains', 'resolve-collisions', '--write', path)

      expect(output[:stdout]).to include('MANUAL: manual_several_in_use', '1 groups need a decision', "Plan written to #{path}")
      expect(JSON.parse(File.read(path))['groups'].first).to include('ascii_name' => 'pair.example', 'decision' => 'manual', 'keep' => nil)
      expect(last_exit_code).to eq(1)
    end

    it 'prints the plan as JSON' do
      allow(op).to receive(:plan).and_return(plan(group('pair.example')))

      output = run_cli_command_quietly('domains', 'resolve-collisions', '--json')
      report = JSON.parse(output[:stdout])

      expect(report['rule_version']).to eq(op_class::Rule::VERSION)
      expect(report['counts']).to include('groups' => 1, 'auto' => 1, 'manual' => 0, 'removals' => 1)
      expect(report['groups'].first['records'].map { |r| r['extid'] }).to eq(%w[cda cdb])
      expect(last_exit_code).to eq(0)
    end

    it 'reports no groups' do
      allow(op).to receive(:plan).and_return(plan)

      output = run_cli_command_quietly('domains', 'resolve-collisions')

      expect(output[:stdout]).to include('No collision groups')
      expect(last_exit_code).to eq(0)
    end

    it 'refuses apply-only options without --apply' do
      output = run_cli_command_quietly('domains', 'resolve-collisions', '--plan', 'x.json')

      expect(output[:stdout]).to include('go with --apply')
      expect(last_exit_code).to eq(1)
    end
  end

  describe '--apply' do
    it 'requires --plan' do
      output = run_cli_command_quietly('domains', 'resolve-collisions', '--apply')

      expect(output[:stdout]).to include('--apply requires --plan')
      expect(last_exit_code).to eq(1)
    end

    it 'refuses a plan file it cannot read or parse' do
      output = run_cli_command_quietly('domains', 'resolve-collisions', '--apply', '--plan', File.join(@dir, 'missing.json'), '--yes')
      expect(output[:stdout]).to include('Cannot read plan')
      expect(last_exit_code).to eq(1)

      bad    = File.join(@dir, 'bad.json')
      File.write(bad, '{"rule_version": 99, "groups": []}')
      output = run_cli_command_quietly('domains', 'resolve-collisions', '--apply', '--plan', bad, '--yes')
      expect(output[:stdout]).to include('Invalid plan', 'rule_version')
      expect(last_exit_code).to eq(1)
    end

    it 'refuses --json without --yes or --dry-run' do
      path = write_plan(@dir, plan(group('pair.example')))

      output = run_cli_command_quietly('domains', 'resolve-collisions', '--apply', '--plan', path, '--json')

      expect(JSON.parse(output[:stdout])).to include('error' => a_string_including('--yes'))
      expect(last_exit_code).to eq(1)
    end

    it 'applies a dry run without prompting and passes the group filter' do
      path = write_plan(@dir, plan(group('pair.example')))
      allow(op).to receive(:apply).and_return(apply_result(:dry_run, dry_run: true))

      output = run_cli_command_quietly('domains', 'resolve-collisions', '--apply', '--plan', path, '--dry-run', '--group', 'pair.example')

      expect(op).to have_received(:apply).with(an_instance_of(op_class::Plan), actor: 'cli', dry_run: true, only: 'pair.example')
      expect(output[:stdout]).to include('DRY RUN', 'planned cda', 'Run again without --dry-run')
      expect(last_exit_code).to eq(0)
    end

    it 'asks before applying and aborts on anything but y' do
      path = write_plan(@dir, plan(group('pair.example')))
      allow(op).to receive(:apply)
      allow($stdin).to receive(:gets).and_return("n\n")

      output = run_cli_command_quietly('domains', 'resolve-collisions', '--apply', '--plan', path)

      expect(output[:stdout]).to include('removes up to 1 custom domain records in 1 groups', 'Aborted')
      expect(op).not_to have_received(:apply)
      expect(last_exit_code).to eq(1)
    end

    it 'applies with --yes and exits 0 when every group applied' do
      path = write_plan(@dir, plan(group('pair.example')))
      allow(op).to receive(:apply).and_return(apply_result(:applied))

      output = run_cli_command_quietly('domains', 'resolve-collisions', '--apply', '--plan', path, '--yes')

      expect(op).to have_received(:apply).with(an_instance_of(op_class::Plan), actor: 'cli', dry_run: false, only: nil)
      expect(output[:stdout]).to include('APPLY', 'pair.example  applied', 'removed cda', 'exact index: created', 'backfill-ascii-index --apply')
      expect(last_exit_code).to eq(0)
    end

    it 'exits 1 when a group was skipped, with the reason, and reports JSON' do
      path = write_plan(@dir, plan(group('pair.example')))
      allow(op).to receive(:apply).and_return(apply_result(:skipped, reason: 'the records sharing the name changed since the plan'))

      output = run_cli_command_quietly('domains', 'resolve-collisions', '--apply', '--plan', path, '--yes')
      expect(output[:stdout]).to include('skipped: the records sharing the name changed since the plan', 'Some groups were skipped')
      expect(last_exit_code).to eq(1)

      output = run_cli_command_quietly('domains', 'resolve-collisions', '--apply', '--plan', path, '--yes', '--json')
      report = JSON.parse(output[:stdout])
      expect(report['counts']).to eq('skipped' => 1)
      expect(report['outcomes'].first).to include('ascii_name' => 'pair.example', 'status' => 'skipped')
      expect(last_exit_code).to eq(1)
    end
  end
end
