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

  def group(ascii_name, decision: :auto, rule: :dns_proof, keep: 'cdb', remove: ['cda'], notes: [], records: nil, approved: false, skip: false)
    op_class::Group.new(
      ascii_name: ascii_name,
      decision: decision,
      rule: rule,
      keep: keep,
      remove: remove,
      notes: notes,
      records: records || [record('a', served: true), record('b', verified_confirmed_at: 1_700_000_100)],
      approved: approved,
      skip: skip,
    )
  end

  def plan(*groups)
    op_class::Plan.new(generated_at: '2026-10-16T00:00:00Z', rule_version: op_class::Rule::VERSION, strategy: 'passthrough', groups: groups)
  end

  def evidence_context(group)
    {
      run_id: '12345678-1234-4123-8123-123456789abc',
      plan_generated_at: '2026-10-16T00:00:00Z',
      rule_version: op_class::Rule::VERSION,
      decision: group.decision.to_s,
      rule: group.rule.to_s,
      approved: group.approved,
      approval_required: group.approval_required?,
      billing_source: 'local_cache',
      records: group.records.map(&:to_h),
      notes: group.notes,
    }
  end

  def billing_group(**over)
    group(
      'pair.example',
      records: [
        record(
          'a',
          served: true,
          org_name: 'Paid Org',
          org_state: :archived,
          ownership_verified: true,
          verified_by_override: true,
          receipts: 7,
          configs: %w[sso mailer],
          all_configs: %w[sso mailer homepage],
          brand: true,
          vhost: true,
          planid: 'paid_plan',
          stripe_customer_id: 'cus_a',
          stripe_subscription_id: 'sub_a',
          subscription_status: 'past_due',
        ),
        record('b', verified_confirmed_at: 1_700_000_100),
      ],
      notes: ['retained evidence note'],
      **over,
    )
  end

  def apply_result(status, dry_run: false, reason: nil, context: {}, errors: [], verify_state: nil)
    removals = []
    unless status == :skipped
      removals << op_class::Removal.new(ref: 'cda', display_domain: 'pair.example', status: dry_run ? :planned : :removed, detail: nil)
    end

    op_class::ApplyResult.new(
      dry_run: dry_run,
      strategy: 'passthrough',
      outcomes: [
        op_class::Outcome.new(
          ascii_name: 'pair.example',
          status: status,
          reason: reason,
          keep: 'cdb',
          removals: removals,
          index_claim: status == :applied ? :created : nil,
          verify_state: verify_state,
          errors: errors,
          context: context,
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
      expect(output[:stdout]).to include('resolve-collisions --apply --plan', 'label=no_local_subscription', 'approval_required=false')
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

    it 'keeps --yes in read-only plan mode without approving anything' do
      proposed = plan(billing_group)
      allow(op).to receive(:plan).and_return(proposed)
      expect(op).not_to receive(:apply)

      output = run_cli_command_quietly('domains', 'resolve-collisions', '--yes', '--json')
      report = JSON.parse(output[:stdout])

      expect(report['groups'].first).to include('decision' => 'auto', 'approved' => false)
      expect(report['counts']).to include('auto' => 1, 'manual' => 0, 'approval_required' => 1, 'approval_pending' => 1)
      expect(last_exit_code).to eq(1)
    end

    it 'distinguishes an auto proposal from pending billing approval and prints full evidence' do
      allow(op).to receive(:plan).and_return(plan(billing_group))

      output = run_cli_command_quietly('domains', 'resolve-collisions')

      expect(output[:stdout]).to include(
        'pair.example  auto: dns_proof',
        'proposal: keep=cdb  decision=auto',
        'approval_required=true  approved=false  approval_pending=true',
        'billing-protected proposed removals: cda',
        'domain_id=a',
        'extid=cda',
        'org_id=org-a',
        'org_extid=ona',
        'org_name="Paid Org"',
        'state=archived',
        'ownership_verified=true',
        'verified_by_override=true',
        'verification_state=pending',
        'historical dns-confirmed',
        'no historical dns confirmation',
        'served',
        'shadow',
        'receipts=7',
        'brand=true',
        'configs=sso,mailer',
        'all_configs=sso,mailer,homepage',
        'non-use configs=homepage',
        'vhost=true',
        'created 2023-11-14T22:13:20Z',
        'source=local_cache',
        'label=live_or_recoverable',
        'protected=true',
        'planid=paid_plan',
        'stripe_customer_id=cus_a',
        'stripe_subscription_id=sub_a',
        'subscription_status=past_due',
        'note: retained evidence note',
        '1 groups need deletion approval',
        '--yes skips the prompt only',
        'not a fresh DNS lookup',
        'no live Stripe lookup',
      )
      expect(output[:stdout]).not_to include('1 groups need a decision')
      expect(last_exit_code).to eq(1)
    end

    it 'does not request approval for a protected keeper alone' do
      kept = billing_group(keep: 'cda', remove: ['cdb'])
      allow(op).to receive(:plan).and_return(plan(kept))

      output = run_cli_command_quietly('domains', 'resolve-collisions')

      expect(output[:stdout]).to include('KEEP   cda', 'approval_required=false  approved=false  approval_pending=false')
      expect(output[:stdout]).not_to include('groups need deletion approval')
      expect(last_exit_code).to eq(0)
    end

    %w[active trialing past_due unpaid canceled incomplete incomplete_expired paused future_status].each do |status|
      it "preserves cached status #{status} and every billing field in plan JSON" do
        snapshot = record('a', planid: 'paid_plan', stripe_customer_id: 'cus_a', stripe_subscription_id: 'sub_a', subscription_status: status)
        allow(op).to receive(:plan).and_return(plan(group('pair.example', records: [snapshot, record('b')])))

        report = JSON.parse(run_cli_command_quietly('domains', 'resolve-collisions', '--json')[:stdout])

        expect(report['groups'].first['records'].first).to include(
          'planid' => 'paid_plan',
          'stripe_customer_id' => 'cus_a',
          'stripe_subscription_id' => 'sub_a',
          'subscription_status' => status,
        )
      end
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

    it 'rejects version-one plans and billing-incomplete snapshots before applying' do
      expect(op).not_to receive(:apply)
      old                 = JSON.parse(plan(group('pair.example')).to_json)
      old['rule_version'] = 1
      path                = File.join(@dir, 'old.json')
      File.write(path, JSON.generate(old))

      output = run_cli_command_quietly('domains', 'resolve-collisions', '--apply', '--plan', path, '--yes')
      expect(output[:stdout]).to include('Invalid plan', 'rule_version')
      expect(last_exit_code).to eq(1)

      old['rule_version'] = op_class::Rule::VERSION
      old['groups'].first['records'].first.delete('subscription_status')
      File.write(path, JSON.generate(old))
      output              = run_cli_command_quietly('domains', 'resolve-collisions', '--apply', '--plan', path, '--yes')
      expect(output[:stdout]).to include('Invalid plan')
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
      expect(output[:stdout]).not_to include('No domain.resolve_collision or domain.remove audit entries are written')
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

    it 'does not turn --yes into approval of a protected automatic removal' do
      protected = billing_group
      path      = write_plan(@dir, plan(protected))
      expect($stdin).not_to receive(:gets)
      expect(op).to receive(:apply) do |loaded, **options|
        expect(options).to eq(actor: 'cli', dry_run: false, only: nil)
        expect(loaded.groups.first.decision).to eq(:auto)
        expect(loaded.groups.first.approved).to be false
        expect(loaded.groups.first).to be_approval_pending
        apply_result(:skipped, reason: 'billing approval required', context: evidence_context(loaded.groups.first))
      end

      output = run_cli_command_quietly('domains', 'resolve-collisions', '--apply', '--plan', path, '--yes')

      expect(output[:stdout]).to include('skipped: billing approval required', 'approval_required=true  approved=false')
      expect(last_exit_code).to eq(1)
    end

    it 'excludes unapproved protected removals from the confirmation count' do
      path = write_plan(@dir, plan(billing_group))
      allow($stdin).to receive(:gets).and_return("n\n")
      expect(op).not_to receive(:apply)

      output = run_cli_command_quietly('domains', 'resolve-collisions', '--apply', '--plan', path)

      expect(output[:stdout]).to include('removes up to 0 custom domain records', 'passing --yes does not approve it', 'Aborted')
      expect(last_exit_code).to eq(1)
    end

    it 'passes an explicitly approved protected group through unchanged' do
      approved = billing_group(approved: true)
      path     = write_plan(@dir, plan(approved))
      expect(op).to receive(:apply) do |loaded, **|
        expect(loaded.groups.first.approved).to be true
        expect(loaded.groups.first).to be_approval_required
        expect(loaded.groups.first).not_to be_approval_pending
        apply_result(:applied, context: evidence_context(loaded.groups.first))
      end

      output = run_cli_command_quietly('domains', 'resolve-collisions', '--apply', '--plan', path, '--yes')

      expect(output[:stdout]).to include('pair.example  applied', 'approval_required=true  approved=true')
      expect(last_exit_code).to eq(0)
    end

    it 'applies with --yes and exits 0 when every group applied' do
      path = write_plan(@dir, plan(group('pair.example')))
      allow(op).to receive(:apply).and_return(apply_result(:applied))

      output = run_cli_command_quietly('domains', 'resolve-collisions', '--apply', '--plan', path, '--yes')

      expect(op).to have_received(:apply).with(an_instance_of(op_class::Plan), actor: 'cli', dry_run: false, only: nil)
      expect(output[:stdout]).to include('APPLY', 'pair.example  applied', 'removed cda', 'exact index: created', 'backfill-ascii-index --apply')
      expect(last_exit_code).to eq(0)
    end

    [:applied, :skipped, :partial, :dry_run].each do |status|
      it "prints full context separately from actual outcomes for #{status}, in text and JSON" do
        proposed = billing_group(approved: status != :skipped)
        context  = evidence_context(proposed)
        dry_run  = status == :dry_run
        reason   = status == :skipped ? 'billing approval required' : nil
        errors   = status == :partial ? ['summary audit failed: domain.resolve_collision'] : []
        verified = status == :applied ? :verified : nil
        result   = apply_result(status, dry_run: dry_run, reason: reason, context: context, errors: errors, verify_state: verified)
        allow(op).to receive(:apply).and_return(result)
        path     = write_plan(@dir, plan(proposed))
        args     = ['domains', 'resolve-collisions', '--apply', '--plan', path, '--yes']
        args << '--dry-run' if dry_run

        text          = run_cli_command_quietly(*args)[:stdout]
        expect(text).to include(
          "pair.example  #{status}",
          "Run ID: #{context[:run_id]}",
          "Plan generated at: #{context[:plan_generated_at]}",
          "Rule version: #{op_class::Rule::VERSION}",
          'decision=auto  rule=dns_proof',
          'billing_source=local_cache',
          'saved plan evidence (KEEP/REMOVE are proposals, not execution results)',
          'domain_id=a',
          'org_id=org-a',
          'org_name="Paid Org"',
          'state=archived',
          'ownership_verified=true',
          'verified_by_override=true',
          'verification_state=pending',
          'historical dns-confirmed',
          'receipts=7',
          'brand=true',
          'all_configs=sso,mailer,homepage',
          'non-use configs=homepage',
          'vhost=true',
          'label=live_or_recoverable',
          'planid=paid_plan',
          'stripe_customer_id=cus_a',
          'stripe_subscription_id=sub_a',
          'subscription_status=past_due',
          'note: retained evidence note',
          verified ? 'kept record verified: verified' : 'kept record verified: no result reported',
        )
        expected_exit = [:skipped, :partial].include?(status) ? 1 : 0
        expect(last_exit_code).to eq(expected_exit)
        if status == :skipped
          expect(text).to include('removal outcomes: none', 'skipped: billing approval required')
          expect(text).not_to match(/^\s+removed cda/)
        else
          expect(text).to include(dry_run ? 'planned cda' : 'removed cda')
        end
        expect(text).to include('error: summary audit failed: domain.resolve_collision') if status == :partial

        report = JSON.parse(run_cli_command_quietly(*args, '--json')[:stdout])
        expect(report['counts']).to eq(status.to_s => 1)
        expect(report['outcomes'].first).to include(
          'status' => status.to_s,
          'reason' => reason,
          'errors' => errors,
          'verify_state' => verified&.to_s,
          'context' => JSON.parse(JSON.generate(context)),
        )
        expect(last_exit_code).to eq(expected_exit)
      end
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

  # Override the CLI metadata so cli_spec_helper does not mock Familia or
  # model instances: this example checks the real CLI-to-operation boundary.
  describe 'real operation dry run', :datastore, type: :datastore do
    include LegacyCustomDomainRecords

    let(:sfx) { SecureRandom.hex(4) }
    let(:name) { "cli-collision-#{sfx}.example" }
    let(:model) { Onetime::CustomDomain }
    let!(:org) do
      Onetime::Organization.new(
        display_name: "CLI collision #{sfx}",
        planid: 'paid',
        stripe_customer_id: "cus_cli_#{sfx}",
        stripe_subscription_id: "sub_cli_#{sfx}",
        subscription_status: 'active',
      ).tap(&:save)
    end
    let!(:keeper_id) { write_legacy_custom_domain(name, org_id: org.objid, fields: { 'ownership_verified' => true }) }
    let!(:loser_id) { write_legacy_custom_domain(name, org_id: org.objid) }

    before do
      allow(op_class).to receive(:new).and_call_original
      allow(OT).to receive(:boot!)
      allow(Onetime::ColonelAuditEvent).to receive(:record).and_call_original
      allow(Onetime::ColonelAuditEvent).to receive(:record_access).and_call_original
    end

    after do
      refs  = [keeper_id, loser_id].map { |id| legacy_custom_domain_extid(id) }
      audit = Onetime::ColonelAuditEvent
      audit.dbclient.zrange(audit.access_events.dbkey, 0, -1).each do |member|
        audit.dbclient.zrem(audit.access_events.dbkey, member) if refs.include?(JSON.parse(member)['target'])
      end
      [keeper_id, loser_id].each { |id| remove_legacy_custom_domain(id, name) }
      Onetime::Organization.load(org.objid)&.destroy!
    end

    it 'runs an approved protected plan through --apply --dry-run --yes --json without domain writes' do
      operation = op_class.new
      proposed  = operation.plan
      selected  = proposed.group(name)
      expect(selected).to be_approval_required
      saved     = proposed.with(groups: [selected.with(approved: true)])
      path      = write_plan(@dir, saved)
      keys      = [model.dbkey(keeper_id), model.dbkey(loser_id), model.display_domain_index.dbkey, model.ascii_display_domain_index.dbkey]
      before    = keys.to_h { |key| [key, model.dbclient.hgetall(key)] }
      expect(Onetime::Operations::Domains::Teardown).not_to receive(:new)
      expect(Onetime::Operations::AdminVerifyDomain).not_to receive(:new)
      expect(model.dbclient).not_to receive(:hset)
      expect(model.dbclient).not_to receive(:hdel)
      expect(model.dbclient).not_to receive(:del)
      expect(model.dbclient).not_to receive(:eval)
      expect(model.dbclient).not_to receive(:evalsha)
      expect(Onetime::ColonelAuditEvent).not_to receive(:record).with(hash_including(verb: 'domain.resolve_collision'))
      expect(Onetime::ColonelAuditEvent).not_to receive(:record).with(hash_including(verb: 'domain.remove', result: :success))
      expect($stdin).not_to receive(:gets)

      output = run_cli_command_quietly('domains', 'resolve-collisions', '--apply', '--plan', path, '--dry-run', '--yes', '--json')
      report = JSON.parse(output[:stdout])

      expect(last_exit_code).to eq(0)
      expect(report).to include('dry_run' => true, 'counts' => { 'dry_run' => 1 })
      expect(report.fetch('outcomes').first).to include(
        'status' => 'dry_run',
        'index_claim' => nil,
        'verify_state' => nil,
        'removals' => [include('ref' => legacy_custom_domain_extid(loser_id), 'status' => 'planned')],
        'context' => include('approved' => true, 'approval_required' => true, 'billing_source' => 'local_cache'),
      )
      expect(keys.to_h { |key| [key, model.dbclient.hgetall(key)] }).to eq(before)
      expect(Onetime::ColonelAuditEvent).to have_received(:record_access).with(
        hash_including(
          verb: 'domain.remove', target: legacy_custom_domain_extid(loser_id), result: 'preview',
        ),
      )
    end
  end
end
