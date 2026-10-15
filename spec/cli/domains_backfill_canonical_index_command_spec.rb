# spec/cli/domains_backfill_canonical_index_command_spec.rb
#
# frozen_string_literal: true

# `bin/ots domains backfill-canonical-index` is a thin adapter over
# Onetime::Operations::Domains::CanonicalIndexBackfill. The op is stubbed with
# results built from its own Data classes; what is under test here is the
# adapter: dry run by default, confirmation before --apply, the exit status,
# and the JSON shape. The op's behaviour against a real datastore is covered
# by spec/unit/onetime/operations/domains/canonical_index_backfill_spec.rb.

require_relative 'cli_spec_helper'

RSpec.describe 'Domains backfill-canonical-index command', type: :cli do
  let(:op_class) { Onetime::Operations::Domains::CanonicalIndexBackfill }
  let(:cli_class) { Onetime::CLI::DomainsBackfillCanonicalIndexCommand }
  let(:audit_class) { Onetime::Operations::Domains::CanonicalIndexAudit }
  let(:missing_only) do
    result(rows: [row(:missing, 'id1', "bu\u0308cher.example")], actions: [action(:claim, :planned, name: "bu\u0308cher.example")])
  end
  let(:collision) do
    result(
      rows: [
        row(:collision, 'id2', 'pair.example', canonical: 'xn--pair.example'),
        row(:collision, 'id3', 'pair.example', canonical: 'xn--pair.example', verified_at: 1_700_000_100),
      ],
    )
  end

  let(:incomplete_apply) do
    result(
      dry_run: false,
      rows: [row(:missing, 'id1', 'm.example'), row(:stale, 'id2', 'stale.example', holder: 'gone')],
      entries: [audit_class::Entry.new(category: :stale, canonical: 'unused.example', holder_id: 'gone2', detail: nil)],
      errors: [audit_class::Unreadable.new(domain_id: 'unreadable-id', message: 'record load failed')],
      actions: [
        action(:claim, :planned),
        action(:reclaim, :planned, id: 'id2', canonical: 'xn--id2.com', name: 'stale.example').with(stale_id: 'gone'),
        action(:release, :planned, id: nil, canonical: 'unused.example', name: nil).with(stale_id: 'gone2'),
      ],
      refusal: :unreadable_records,
    )
  end

  def row(category, id, name, canonical: "xn--#{id}.com", holder: nil, verified_at: nil)
    audit_class::Row.new(
      category: category,
      domain_id: id,
      extid: "cd#{id}",
      display_domain: name,
      canonical: canonical,
      holder_id: holder,
      org_id: "org-#{id}",
      verification_state: :pending,
      ownership_verified: !verified_at.nil?,
      verified_by_override: false,
      verified_confirmed_at: verified_at,
      created: 1_700_000_000,
      detail: nil,
    )
  end

  def action(kind, outcome, id: 'id1', canonical: 'xn--id1.com', name: 'm.example')
    op_class::Action.new(
      kind: kind,
      canonical: canonical,
      domain_id: id,
      display_domain: name,
      stale_id: nil,
      outcome: outcome,
      detail: nil,
    )
  end

  # final_rows: the audit after an apply (defaults to the audit before it).
  def result(rows:, actions: [], dry_run: true, entries: [], errors: [], final_rows: nil, refusal: nil)
    audit = audit_class::Result.new(rows: rows, entries: entries, errors: errors)
    final = final_rows ? audit_class::Result.new(rows: final_rows, entries: [], errors: []) : audit
    op_class::Result.new(
      dry_run: dry_run,
      audit: audit,
      actions: actions,
      final_audit: final,
      recheck_error: nil,
      refusal: refusal,
    )
  end

  def stub_op(*results)
    ops = results.map { |res| double('CanonicalIndexBackfill', call: res) }
    allow(op_class).to receive(:new).and_return(*ops)
  end

  it 'runs a dry run by default and exits 0 when nothing needs an operator' do
    stub_op(missing_only)

    output = run_cli_command_quietly('domains', 'backfill-canonical-index')

    expect(op_class).to have_received(:new).with(dry_run: true)
    expect([output[:stdout], last_exit_code]).to match([a_string_including('DRY RUN', '--apply'), 0])
  end

  it 'shows a non-ASCII name escaped as well, so decomposed and composed spellings differ' do
    stub_op(missing_only)

    output = run_cli_command_quietly('domains', 'backfill-canonical-index')

    expect(output[:stdout]).to include('bu\u0308cher.example')
  end

  it 'exits 1 and lists every record of a collision group' do
    stub_op(collision)

    output = run_cli_command_quietly('domains', 'backfill-canonical-index')

    expect(output[:stdout]).to include('Collision groups', 'cdid2', 'cdid3', 'bin/ots domains remove <extid>')
    expect(last_exit_code).to eq(1)
  end

  it 'exits 1 on a conflict' do
    stub_op(result(rows: [row(:conflict, 'id4', 'c.example', holder: 'other')]))

    run_cli_command_quietly('domains', 'backfill-canonical-index')

    expect(last_exit_code).to eq(1)
  end

  it 'exits 1 when a write did not land' do
    stub_op(result(rows: [row(:missing, 'id1', 'm.example')], actions: [action(:claim, :refused)], dry_run: false))

    run_cli_command_quietly('domains', 'backfill-canonical-index', '--apply', '--yes')

    expect(last_exit_code).to eq(1)
  end

  describe 'after --apply' do
    it 'reports the counts from the audit after the writes' do
      stub_op(
        result(
          rows: [row(:missing, 'id1', 'm.example')],
          actions: [action(:claim, :claimed)],
          dry_run: false,
          final_rows: [row(:ok, 'id1', 'm.example', holder: 'id1')],
        ),
      )

      report = JSON.parse(run_cli_command_quietly('domains', 'backfill-canonical-index', '--apply', '--yes', '--json')[:stdout])

      expect([report['counts'].slice('ok', 'missing'), report['counts_before'].slice('ok', 'missing'), last_exit_code])
        .to eq([{ 'ok' => 1, 'missing' => 0 }, { 'ok' => 0, 'missing' => 1 }, 0])
    end

    it 'exits 1 when a skipped claim leaves a record missing' do
      stub_op(
        result(
          rows: [row(:missing, 'id1', 'm.example')],
          actions: [action(:claim, :skipped)],
          dry_run: false,
          final_rows: [row(:missing, 'id1', 'm.example')],
        ),
      )

      output = run_cli_command_quietly('domains', 'backfill-canonical-index', '--apply', '--yes')

      expect([output[:stdout], last_exit_code]).to match([a_string_including('still missing'), 1])
    end

    it 'prints the outcome of every action, past the text limit, and exits 1 on an error' do
      count   = cli_class::TEXT_ACTION_LIMIT + 5
      actions = Array.new(count) { |i| action(:claim, i.zero? ? :error : :claimed, id: "id#{i}", canonical: "xn--id#{i}.com") }
      stub_op(result(rows: [], actions: actions, dry_run: false))

      output = run_cli_command_quietly('domains', 'backfill-canonical-index', '--apply', '--yes')

      expect([output[:stdout].scan(/^  claim +(?:claimed|error) /).size, output[:stdout]]).to match([count, a_string_including('error')])
      expect(last_exit_code).to eq(1)
    end
  end

  describe '--apply' do
    it 'asks whether the application is stopped and writes nothing on no' do
      stub_op(missing_only)
      allow($stdin).to receive(:gets).and_return("n\n")

      output = run_cli_command_quietly('domains', 'backfill-canonical-index', '--apply')

      expect(op_class).not_to have_received(:new)
      expect([output[:stdout], last_exit_code]).to match([a_string_including('Is the application stopped?'), 1])
    end

    it 'writes nothing when the prompt reads no input' do
      stub_op(missing_only)
      allow($stdin).to receive(:gets).and_return(nil)

      run_cli_command_quietly('domains', 'backfill-canonical-index', '--apply')

      expect(op_class).not_to have_received(:new)
      expect(last_exit_code).to eq(1)
    end

    it 'runs the op with dry_run: false after yes' do
      stub_op(result(rows: [row(:ok, 'id1', 'ok.example')], dry_run: false))
      allow($stdin).to receive(:gets).and_return("y\n")

      run_cli_command_quietly('domains', 'backfill-canonical-index', '--apply')

      expect(op_class).to have_received(:new).with(dry_run: false)
      expect(last_exit_code).to eq(0)
    end

    it 'skips the prompt with --yes' do
      stub_op(result(rows: [row(:ok, 'id1', 'ok.example')], dry_run: false))
      allow($stdin).to receive(:gets)

      run_cli_command_quietly('domains', 'backfill-canonical-index', '--apply', '--yes')

      expect($stdin).not_to have_received(:gets)
      expect(op_class).to have_received(:new).with(dry_run: false)
    end

    it 'reports a refused apply with its planned writes, writes nothing, and exits 1' do
      stub_op(incomplete_apply)

      output = run_cli_command_quietly('domains', 'backfill-canonical-index', '--apply', '--yes')

      expect(op_class).to have_received(:new).with(dry_run: false)
      expect(output[:stdout]).to include(
        'APPLY REFUSED (nothing written)', 'Planned writes (not applied):', 'planned',
        'unreadable-id: record load failed',
        'Nothing was written. 1 records could not be loaded',
      )
      expect(output[:stdout]).not_to include('The canonical index agrees with every record.')
      expect(last_exit_code).to eq(1)
    end

    it 'retains unreadable errors and every planned action in JSON for a refused apply, and exits 1' do
      stub_op(incomplete_apply)

      report = JSON.parse(run_cli_command_quietly('domains', 'backfill-canonical-index', '--apply', '--yes', '--json')[:stdout])

      expect(report.slice('dry_run', 'applied', 'refusal', 'attention')).to eq(
        'dry_run' => false, 'applied' => false, 'refusal' => 'unreadable_records', 'attention' => true,
      )
      expect(report).not_to have_key('counts_before')
      expect(report['counts']).to include('unreadable' => 1)
      expect(report['unreadable']).to eq([{ 'domain_id' => 'unreadable-id', 'message' => 'record load failed' }])
      expect(report['actions'].map { |item| item['kind'] }).to eq(%w[claim reclaim release])
      expect(report['actions']).to all(include('outcome' => 'planned', 'detail' => nil))
      expect(last_exit_code).to eq(1)
    end

    it 'refuses --json without --yes' do
      stub_op(missing_only)

      output = run_cli_command_quietly('domains', 'backfill-canonical-index', '--apply', '--json')

      expect(op_class).not_to have_received(:new)
      expect([JSON.parse(output[:stdout])['error'], last_exit_code]).to match([a_string_including('--yes'), 1])
    end
  end

  it 'prints counts, collision groups, non-ok rows and actions as JSON' do
    stub_op(collision)

    report = JSON.parse(run_cli_command_quietly('domains', 'backfill-canonical-index', '--json')[:stdout])

    expect(report.slice('dry_run', 'attention', 'collision_groups')).to eq(
      'dry_run' => true, 'attention' => true, 'collision_groups' => { 'xn--pair.example' => %w[id2 id3] },
    )
    expect(report['counts']).to include('collision' => 2, 'missing' => 0, 'unreadable' => 0)
    expect(report['rows'].map { |r| r['extid'] }).to eq(%w[cdid2 cdid3])
  end

  it 'reports incomplete dry-run plans without suggesting they can be applied' do
    stub_op(incomplete_apply.with(dry_run: true, refusal: nil))

    output = run_cli_command_quietly('domains', 'backfill-canonical-index')

    expect(op_class).to have_received(:new).with(dry_run: true)
    expect(output[:stdout]).to include(
      'DRY RUN (nothing written)', 'Planned writes:',
      '1 records could not be loaded; --apply writes nothing while',
    )
    expect(output[:stdout]).not_to include('With the application stopped, apply with:', 'Nothing was written.')
    expect(last_exit_code).to eq(1)
  end

  it 'says in its help that --apply writes nothing while a record cannot be loaded' do
    output = run_cli_command_quietly('domains', 'backfill-canonical-index', '--help')

    expect(output[:stdout]).to include('--apply writes nothing while any record cannot')
  end

  it 'says in its help that the application must be stopped' do
    output = run_cli_command_quietly('domains', 'backfill-canonical-index', '--help')

    expect(output[:stdout]).to include('STOP THE APPLICATION BEFORE --apply')
  end
end
