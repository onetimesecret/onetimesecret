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
# dry_run: false, --limit is forwarded, --json emits the documented document
# and nothing else on stdout, and --help renders.
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

  def build_result(dry_run:)
    double('Result', dry_run: dry_run, stats: stats, rows: rows)
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
  end

  describe '--json' do
    it 'emits exactly one JSON document {dry_run, stats, rows} and nothing else on stdout' do
      output  = run_cli_command_quietly('customers', 'normalize-emails', '--json')
      payload = JSON.parse(output[:stdout])

      expect(payload.keys).to match_array(%w[dry_run stats rows])
      expect(payload['dry_run']).to be(true)
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
      expect(op).not_to have_received(:call)
    end
  end
end
