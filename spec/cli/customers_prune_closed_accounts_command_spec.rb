# spec/cli/customers_prune_closed_accounts_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

# The CLI manifest (lib/onetime/cli.rb) require is applied centrally; require
# the command here so the registry has it regardless of manifest ordering.
require 'sequel'
require 'onetime/cli/customers/prune_closed_accounts_command'
require 'auth/operations/customers/prune_closed_accounts'

# CLI-layer coverage only (#4819). The deletion itself is covered by
# apps/web/auth/spec/integration/full/prune_closed_accounts_spec.rb; these
# examples assert what the ADAPTER adds: dry run by default, --confirm threads
# dry_run: false, the report names the counts, --json emits the documented
# document and nothing else on stdout, a missing auth database exits 1, a
# database or Redis failure during the run exits 1 the same way (under --json too),
# and --help renders.
RSpec.describe 'customers prune-closed-accounts', type: :cli do
  let(:op) { instance_double(Auth::Operations::Customers::PruneClosedAccounts) }

  def build_result(dry_run:, accounts: 2, rows: { account_authentication_audit_logs: 17 }, marked: 0)
    Auth::Operations::Customers::PruneClosedAccounts::Result.new(
      dry_run: dry_run, accounts: accounts, rows: rows, marked: marked,
    )
  end

  before do
    allow(Auth::Operations::Customers::PruneClosedAccounts).to receive(:new).and_return(op)
    allow(op).to receive(:call).and_return(build_result(dry_run: true))
  end

  describe 'dry run by default' do
    it 'constructs the op with dry_run: true, reports the counts and exits 0' do
      output = run_cli_command_quietly('customers', 'prune-closed-accounts')

      expect(Auth::Operations::Customers::PruneClosedAccounts).to have_received(:new).with(dry_run: true)
      expect(op).to have_received(:call)
      expect(output[:stdout]).to include('DRY RUN')
      expect(output[:stdout]).to include('Would delete closed accounts rows:')
      expect(output[:stdout]).to include('Would delete account_authentication_audit_logs rows:')
      expect(output[:stdout]).to include('--confirm')
      expect(last_exit_code).to eq(0)
    end

    it 'names the customer records it would mark and points at finish-closures' do
      allow(op).to receive(:call).and_return(build_result(dry_run: true, marked: 3))

      output = run_cli_command_quietly('customers', 'prune-closed-accounts')

      expect(output[:stdout]).to include('Would mark customer records as closing:')
      expect(output[:stdout]).to include('bin/ots customers finish-closures --confirm')
    end

    it 'says so when there is nothing to prune' do
      allow(op).to receive(:call).and_return(build_result(dry_run: true, accounts: 0, rows: {}))

      output = run_cli_command_quietly('customers', 'prune-closed-accounts')

      expect(output[:stdout]).to include('Nothing to prune')
      expect(output[:stdout]).not_to include('Review the counts above')
    end
  end

  describe '--confirm' do
    before do
      allow(op).to receive(:call).and_return(build_result(dry_run: false))
    end

    it 'constructs the op with dry_run: false and exits 0' do
      output = run_cli_command_quietly('customers', 'prune-closed-accounts', '--confirm')

      expect(Auth::Operations::Customers::PruneClosedAccounts).to have_received(:new).with(dry_run: false)
      expect(output[:stdout]).not_to include('DRY RUN')
      expect(output[:stdout]).to include('Deleted closed accounts rows:')
      expect(last_exit_code).to eq(0)
    end
  end

  describe '--json' do
    it 'emits exactly one JSON document {dry_run, accounts, rows, marked} and nothing else on stdout' do
      output  = run_cli_command_quietly('customers', 'prune-closed-accounts', '--json')
      payload = JSON.parse(output[:stdout])

      expect(payload.keys).to match_array(%w[dry_run accounts rows marked])
      expect(payload['marked']).to eq(0)
      expect(payload['dry_run']).to be(true)
      expect(payload['accounts']).to eq(2)
      expect(payload['rows']).to eq('account_authentication_audit_logs' => 17)
      expect(last_exit_code).to eq(0)
    end
  end

  describe 'without an auth database' do
    before do
      allow(Auth::Operations::Customers::PruneClosedAccounts).to receive(:new)
        .and_raise(Onetime::Problem, 'Auth database unavailable (simple auth mode?)')
    end

    it 'exits 1 with the reason' do
      output = run_cli_command_quietly('customers', 'prune-closed-accounts')

      expect(last_exit_code).to eq(1)
      expect(output[:stderr]).to include('Auth database unavailable')
    end

    it 'reports the reason as JSON under --json' do
      output = run_cli_command_quietly('customers', 'prune-closed-accounts', '--json')

      expect(last_exit_code).to eq(1)
      expect(JSON.parse(output[:stdout])).to include('error' => a_string_including('Auth database unavailable'))
    end
  end

  # The op connects lazily: an unreachable database surfaces from op.call,
  # not from PruneClosedAccounts.new.
  describe 'when the database fails during the run' do
    before do
      allow(op).to receive(:call).and_raise(Sequel::DatabaseConnectionError, 'could not connect to server')
    end

    it 'exits 1 with the reason on stderr' do
      output = run_cli_command_quietly('customers', 'prune-closed-accounts', '--confirm')

      expect(last_exit_code).to eq(1)
      expect(output[:stderr]).to include('could not connect to server')
      expect(output[:stdout]).not_to include('Deleted closed accounts rows')
    end

    it 'reports the reason as JSON under --json and nothing else on stdout' do
      output = run_cli_command_quietly('customers', 'prune-closed-accounts', '--json')

      expect(last_exit_code).to eq(1)
      expect(JSON.parse(output[:stdout])).to eq('error' => 'Pruning failed: could not connect to server')
    end
  end

  describe 'when Redis is unreachable' do
    before do
      allow(op).to receive(:call).and_raise(Redis::CannotConnectError, 'valkey unavailable')
    end

    it 'reports the reason as JSON under --json, exit 1' do
      output = run_cli_command_quietly('customers', 'prune-closed-accounts', '--confirm', '--json')

      expect(last_exit_code).to eq(1)
      expect(JSON.parse(output[:stdout])).to eq('error' => 'Pruning failed: valkey unavailable')
    end
  end

  describe '--help' do
    it 'renders usage without calling the op' do
      output = run_cli_command_quietly('customers', 'prune-closed-accounts', '--help')

      expect(output[:stdout]).to include('bin/ots customers prune-closed-accounts [options]')
      expect(op).not_to have_received(:call)
      expect(last_exit_code).to eq(0)
    end
  end
end
