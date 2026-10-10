# spec/cli/customers_normalize_emails_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

# The CLI manifest (lib/onetime/cli.rb) require is applied centrally; require
# the command here so the registry has it regardless of manifest ordering.
require 'onetime/cli/customers/normalize_emails_command'
require 'auth/operations/customers/normalize_account_emails'

# CLI-layer coverage only (#4726). The per-row repair rules are covered by
# apps/web/auth/spec/integration/full/normalize_account_emails_spec.rb; these
# examples assert what the ADAPTER adds: dry run by default, --confirm threads
# dry_run: false, --limit and --after-id are forwarded, the resume hint is
# printed, --json emits the documented document and nothing else on stdout,
# the exit code is 1 when any row errored, and --help renders.
RSpec.describe 'customers normalize-emails', type: :cli do
  let(:op) { instance_double(Auth::Operations::Customers::NormalizeAccountEmails) }

  let(:stats) do
    {
      scanned: 2,
      normalized: 1,
      skipped_fold_unstable: 0,
      skipped_sql_collision: 1,
      skipped_index_collision: 0,
      skipped_no_customer: 0,
      error: 0,
    }
  end

  let(:rows) do
    [
      { account_id: 7, outcome: :normalized, from: 'Ja***@***.com', to: 'ja***@***.com', detail: nil },
      { account_id: 9, outcome: :skipped_sql_collision, from: 'Du***@***.com', to: 'du***@***.com',
        detail: 'collides with account 10' },
    ]
  end

  def build_result(dry_run:, stats: self.stats, rows: self.rows, last_account_id: 9)
    double('Result', dry_run: dry_run, stats: stats, rows: rows, last_account_id: last_account_id)
  end

  # One row ChangeEmail refused at write time (compare-and-set matched 0 rows).
  let(:error_stats) { stats.merge(error: 1, scanned: 3) }
  let(:error_rows) do
    rows + [
      { account_id: 11, outcome: :error, from: 'Er***@***.com', to: 'er***@***.com',
        detail: 'accounts row 11 no longer held the scanned address at write time; nothing written; re-run' },
    ]
  end

  before do
    allow(Auth::Operations::Customers::NormalizeAccountEmails).to receive(:new).and_return(op)
    allow(op).to receive(:call).and_return(build_result(dry_run: true))
  end

  describe 'dry run by default' do
    it 'constructs the op with dry_run: true and exits 0' do
      output = run_cli_command_quietly('customers', 'normalize-emails')

      expect(Auth::Operations::Customers::NormalizeAccountEmails).to have_received(:new)
        .with(hash_including(dry_run: true))
      expect(op).to have_received(:call)
      expect(output[:stdout]).to include('DRY RUN')
      expect(last_exit_code).to eq(0)
    end

    it 'points the operator at --confirm' do
      output = run_cli_command_quietly('customers', 'normalize-emails')

      expect(output[:stdout]).to include('--confirm')
    end
  end

  describe '--confirm' do
    before do
      allow(op).to receive(:call).and_return(build_result(dry_run: false))
    end

    it 'constructs the op with dry_run: false and exits 0' do
      output = run_cli_command_quietly('customers', 'normalize-emails', '--confirm')

      expect(Auth::Operations::Customers::NormalizeAccountEmails).to have_received(:new)
        .with(hash_including(dry_run: false))
      expect(output[:stdout]).not_to include('DRY RUN')
      expect(last_exit_code).to eq(0)
    end
  end

  describe '--limit' do
    it 'forwards the cap to the op' do
      run_cli_command_quietly('customers', 'normalize-emails', '--limit', '5')

      expect(Auth::Operations::Customers::NormalizeAccountEmails).to have_received(:new)
        .with(hash_including(limit: 5))
    end

    it 'passes limit: nil when not given' do
      run_cli_command_quietly('customers', 'normalize-emails')

      expect(Auth::Operations::Customers::NormalizeAccountEmails).to have_received(:new)
        .with(hash_including(limit: nil))
    end

    it 'rejects a non-positive or non-integer value with exit 1 and never calls the op' do
      output = run_cli_command_quietly('customers', 'normalize-emails', '--limit', 'ten')

      expect(last_exit_code).to eq(1)
      expect(output[:stderr]).to include('--limit must be a positive integer')
      expect(op).not_to have_received(:call)
    end

    # A refused low-id row is re-selected by every limited run; the hint names
    # the id to resume past so the operator is not stuck on it.
    it 'prints the resume hint with the last processed id (no --confirm on a dry run)' do
      output = run_cli_command_quietly('customers', 'normalize-emails', '--limit', '2')

      expect(output[:stdout]).to include('Resume with:')
      expect(output[:stdout]).to include('bin/ots customers normalize-emails --limit 2 --after-id 9')
      expect(output[:stdout]).not_to include('--after-id 9 --confirm')
    end

    it 'keeps --confirm on the resume hint for a live run' do
      allow(op).to receive(:call).and_return(build_result(dry_run: false))

      output = run_cli_command_quietly('customers', 'normalize-emails', '--limit', '2', '--confirm')

      expect(output[:stdout]).to include('bin/ots customers normalize-emails --limit 2 --after-id 9 --confirm')
    end

    it 'prints no resume hint when the scan found nothing' do
      allow(op).to receive(:call).and_return(
        build_result(dry_run: true, stats: stats.merge(scanned: 0, normalized: 0, skipped_sql_collision: 0),
                     rows: [], last_account_id: nil),
      )

      output = run_cli_command_quietly('customers', 'normalize-emails', '--limit', '2')

      expect(output[:stdout]).not_to include('Resume with:')
    end

    it 'prints no resume hint without --limit' do
      output = run_cli_command_quietly('customers', 'normalize-emails')

      expect(output[:stdout]).not_to include('Resume with:')
    end
  end

  describe '--after-id' do
    it 'forwards the lower bound to the op' do
      run_cli_command_quietly('customers', 'normalize-emails', '--after-id', '900')

      expect(Auth::Operations::Customers::NormalizeAccountEmails).to have_received(:new)
        .with(hash_including(after_id: 900))
    end

    it 'passes after_id: nil when not given' do
      run_cli_command_quietly('customers', 'normalize-emails')

      expect(Auth::Operations::Customers::NormalizeAccountEmails).to have_received(:new)
        .with(hash_including(after_id: nil))
    end

    it 'rejects a negative or non-integer value with exit 1 and never calls the op' do
      output = run_cli_command_quietly('customers', 'normalize-emails', '--after-id', '-1')

      expect(last_exit_code).to eq(1)
      expect(output[:stderr]).to include('--after-id must be a non-negative integer')
      expect(op).not_to have_received(:call)
    end

    it 'reports the operator error as JSON under --json' do
      output = run_cli_command_quietly('customers', 'normalize-emails', '--after-id', 'abc', '--json')

      expect(last_exit_code).to eq(1)
      expect(JSON.parse(output[:stdout])).to include('error' => a_string_including('--after-id'))
    end
  end

  describe '--json' do
    it 'emits exactly one JSON document {dry_run, stats, rows, last_account_id} and nothing else on stdout' do
      output  = run_cli_command_quietly('customers', 'normalize-emails', '--json')
      payload = JSON.parse(output[:stdout])

      expect(payload.keys).to match_array(%w[dry_run stats rows last_account_id])
      expect(payload['dry_run']).to be(true)
      expect(payload['last_account_id']).to eq(9)
      expect(payload['stats']).to eq(stats.transform_keys(&:to_s))
      expect(payload['rows'].size).to eq(2)
      expect(payload['rows'].first).to include(
        'account_id' => 7,
        'outcome' => 'normalized',
        'from' => 'Ja***@***.com',
        'to' => 'ja***@***.com',
      )
      expect(payload['rows'].last).to include('detail' => 'collides with account 10')
      expect(last_exit_code).to eq(0)
    end

    it 'reports dry_run false under --confirm --json' do
      allow(op).to receive(:call).and_return(build_result(dry_run: false))

      output  = run_cli_command_quietly('customers', 'normalize-emails', '--confirm', '--json')
      payload = JSON.parse(output[:stdout])

      expect(payload['dry_run']).to be(false)
      expect(Auth::Operations::Customers::NormalizeAccountEmails).to have_received(:new)
        .with(hash_including(dry_run: false))
    end

    it 'emits last_account_id: null when the scan found nothing' do
      allow(op).to receive(:call).and_return(build_result(dry_run: true, rows: [], last_account_id: nil))

      payload = JSON.parse(run_cli_command_quietly('customers', 'normalize-emails', '--json')[:stdout])

      expect(payload).to include('last_account_id' => nil)
    end
  end

  # Sibling repair commands (purge, migrate, doctor, change-email) exit 1 on a
  # per-record failure; this one did not. The whole report is still printed
  # first so the exit code never hides the row that caused it.
  describe 'exit code on error rows' do
    before do
      allow(op).to receive(:call).and_return(build_result(dry_run: false, stats: error_stats, rows: error_rows))
    end

    it 'exits 1 after printing the full human report' do
      output = run_cli_command_quietly('customers', 'normalize-emails', '--confirm')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Normalization Complete')
      expect(output[:stdout]).to include('nothing written; re-run')
      expect(output[:stdout]).to match(/Errors:\s+1/)
    end

    it 'exits 1 after emitting the full JSON document' do
      output  = run_cli_command_quietly('customers', 'normalize-emails', '--confirm', '--json')
      payload = JSON.parse(output[:stdout])

      expect(last_exit_code).to eq(1)
      expect(payload['stats']['error']).to eq(1)
      expect(payload['rows'].size).to eq(3)
    end

    it 'exits 1 on a dry run too (the gate is the error count, not the mode)' do
      allow(op).to receive(:call).and_return(build_result(dry_run: true, stats: error_stats, rows: error_rows))

      run_cli_command_quietly('customers', 'normalize-emails')

      expect(last_exit_code).to eq(1)
    end

    it 'tells :partial rows apart from untouched ones in the footer' do
      output = run_cli_command_quietly('customers', 'normalize-emails', '--confirm')

      expect(output[:stdout]).to include('nothing was written are untouched')
      expect(output[:stdout]).to include(':partial')
      expect(output[:stdout]).to include('bin/ots customers doctor <extid>')
    end

    it 'exits 0 when no row errored (refusals are not errors)' do
      allow(op).to receive(:call).and_return(build_result(dry_run: false))

      run_cli_command_quietly('customers', 'normalize-emails', '--confirm')

      expect(last_exit_code).to eq(0)
    end
  end

  describe 'human output' do
    it 'renders the stats and the per-row outcomes with detail' do
      output = run_cli_command_quietly('customers', 'normalize-emails')

      expect(output[:stdout]).to include('normalized')
      expect(output[:stdout]).to include('skipped_sql_collision')
      expect(output[:stdout]).to include('collides with account 10')
      expect(output[:stdout]).to include('Ja***@***.com')
    end
  end

  describe '--help' do
    it 'renders usage listing the options and exits 0' do
      output = run_cli_command_quietly('customers', 'normalize-emails', '--help')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('--confirm')
      expect(output[:stdout]).to include('--json')
      expect(output[:stdout]).to include('--limit')
      expect(output[:stdout]).to include('--after-id')
      expect(op).not_to have_received(:call)
    end
  end
end
