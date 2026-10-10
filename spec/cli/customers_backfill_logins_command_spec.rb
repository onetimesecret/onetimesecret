# spec/cli/customers_backfill_logins_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

require 'onetime/cli/customers/backfill_logins_command'
require 'auth/operations/backfill_account_logins'

# CLI-layer coverage only (ADR-051). The per-row rules are covered by
# apps/web/auth/spec/integration/full/backfill_account_logins_spec.rb; these
# examples assert what the ADAPTER adds: dry run by default, --confirm threads
# dry_run: false, --limit / --after-id / --mint-missing are forwarded, the
# resume hint is printed, --json emits the documented document and nothing
# else, the exit code is 1 when any row errored, and --help renders.
RSpec.describe 'customers backfill-logins', type: :cli do
  let(:op) { instance_double(Auth::Operations::BackfillAccountLogins) }

  let(:stats) do
    {
      scanned: 3, backfilled: 2, by_external_id: 1, by_email: 1, minted: 0,
      skipped_dangling_external_id: 0, skipped_ambiguous_customer: 0,
      skipped_customer_linked_elsewhere: 0, skipped_no_customer: 1, error: 0,
    }
  end

  let(:rows) do
    [
      { account_id: 7, outcome: :backfilled, branch: :by_external_id, email: 'ja***@***.com', detail: 'set login, email_verified_by=email' },
      { account_id: 8, outcome: :backfilled, branch: :by_email, email: 'jo***@***.com', detail: 'set login and external_id, email unverified' },
      { account_id: 9, outcome: :skipped_no_customer, branch: nil, email: 'no***@***.com', detail: 'no Customer' },
    ]
  end

  def build_result(dry_run:, stats: self.stats, rows: self.rows, last_account_id: 9)
    double('Result', dry_run: dry_run, stats: stats, rows: rows, last_account_id: last_account_id)
  end

  before do
    allow(Auth::Operations::BackfillAccountLogins).to receive(:new).and_return(op)
    allow(op).to receive(:call).and_return(build_result(dry_run: true))
  end

  describe 'dry run by default' do
    it 'constructs the op with dry_run: true, mint_missing: false and exits 0' do
      output = run_cli_command_quietly('customers', 'backfill-logins')

      expect(Auth::Operations::BackfillAccountLogins).to have_received(:new)
        .with(hash_including(dry_run: true, mint_missing: false, limit: nil, after_id: nil))
      expect(op).to have_received(:call)
      expect(output[:stdout]).to include('DRY RUN')
      expect(output[:stdout]).to include('--confirm')
      expect(last_exit_code).to eq(0)
    end

    it 'never prints a login value (reports carry only the obscured email)' do
      output = run_cli_command_quietly('customers', 'backfill-logins')

      expect(output[:stdout]).to include('ja***@***.com')
      expect(output[:stdout]).not_to match(/[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}/)
    end
  end

  describe '--confirm' do
    before { allow(op).to receive(:call).and_return(build_result(dry_run: false)) }

    it 'constructs the op with dry_run: false' do
      output = run_cli_command_quietly('customers', 'backfill-logins', '--confirm')

      expect(Auth::Operations::BackfillAccountLogins).to have_received(:new)
        .with(hash_including(dry_run: false))
      expect(output[:stdout]).not_to include('DRY RUN')
      expect(last_exit_code).to eq(0)
    end
  end

  describe '--mint-missing' do
    it 'forwards mint_missing: true and keeps it on the resume hint' do
      output = run_cli_command_quietly('customers', 'backfill-logins', '--mint-missing', '--limit', '2')

      expect(Auth::Operations::BackfillAccountLogins).to have_received(:new)
        .with(hash_including(mint_missing: true, limit: 2))
      expect(output[:stdout]).to include('bin/ots customers backfill-logins --limit 2 --after-id 9 --mint-missing')
    end
  end

  describe '--limit / --after-id' do
    it 'forwards both' do
      run_cli_command_quietly('customers', 'backfill-logins', '--limit', '5', '--after-id', '100')

      expect(Auth::Operations::BackfillAccountLogins).to have_received(:new)
        .with(hash_including(limit: 5, after_id: 100))
    end

    it 'rejects a non-integer --limit with exit 1 and never calls the op' do
      output = run_cli_command_quietly('customers', 'backfill-logins', '--limit', 'ten')

      expect(last_exit_code).to eq(1)
      expect(output[:stderr]).to include('--limit must be a positive integer')
      expect(op).not_to have_received(:call)
    end

    it 'rejects a negative --after-id' do
      output = run_cli_command_quietly('customers', 'backfill-logins', '--after-id', '-1')

      expect(last_exit_code).to eq(1)
      expect(output[:stderr]).to include('--after-id must be a non-negative integer')
    end

    it 'prints the resume hint, with --confirm only on a live run' do
      output = run_cli_command_quietly('customers', 'backfill-logins', '--limit', '2')
      expect(output[:stdout]).to include('bin/ots customers backfill-logins --limit 2 --after-id 9')
      expect(output[:stdout]).not_to include('--after-id 9 --confirm')

      allow(op).to receive(:call).and_return(build_result(dry_run: false))
      output = run_cli_command_quietly('customers', 'backfill-logins', '--limit', '2', '--confirm')
      expect(output[:stdout]).to include('bin/ots customers backfill-logins --limit 2 --after-id 9 --confirm')
    end
  end

  describe 'skipped_no_customer guidance' do
    it 'tells the operator when --mint-missing becomes safe' do
      output = run_cli_command_quietly('customers', 'backfill-logins')

      expect(output[:stdout]).to include('--mint-missing')
      expect(output[:stdout]).to include('creates a missing one from `login`')
    end
  end

  describe '--json' do
    it 'emits only the documented document' do
      output = run_cli_command_quietly('customers', 'backfill-logins', '--json')

      doc = JSON.parse(output[:stdout])
      expect(doc.keys).to match_array(%w[dry_run stats rows last_account_id])
      expect(doc['dry_run']).to be(true)
      expect(doc['stats']['backfilled']).to eq(2)
      expect(doc['rows'].size).to eq(3)
      expect(doc['last_account_id']).to eq(9)
    end
  end

  describe 'exit code' do
    it 'is 1 when any row errored, after printing the report' do
      allow(op).to receive(:call).and_return(
        build_result(dry_run: false, stats: stats.merge(error: 1, scanned: 4),
                     rows: rows + [{ account_id: 11, outcome: :error, branch: :by_email, email: 'er***@***.com', detail: 'boom' }]),
      )

      output = run_cli_command_quietly('customers', 'backfill-logins', '--confirm')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Errors:')
      expect(output[:stdout]).to include('boom')
    end

    it 'is 1 with the message when the op cannot be built (no auth DB)' do
      allow(Auth::Operations::BackfillAccountLogins).to receive(:new)
        .and_raise(Onetime::Problem, 'Auth database unavailable (simple auth mode?)')

      output = run_cli_command_quietly('customers', 'backfill-logins')

      expect(last_exit_code).to eq(1)
      expect(output[:stderr]).to include('Cannot backfill: Auth database unavailable')
    end
  end

  describe '--help' do
    it 'renders usage and never calls the op' do
      output = run_cli_command_quietly('customers', 'backfill-logins', '--help')

      expect(output[:stdout]).to include('bin/ots customers backfill-logins [options]')
      expect(output[:stdout]).to include('--mint-missing')
      expect(op).not_to have_received(:call)
    end
  end
end
