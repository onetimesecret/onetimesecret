# spec/cli/customers_finish_closures_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

# The CLI manifest (lib/onetime/cli.rb) require is applied centrally; require
# the command here so the registry has it regardless of manifest ordering.
require 'sequel'
require 'onetime/cli/customers/finish_closures_command'
require 'auth/operations/customers/finish_closures'

# CLI-layer coverage only (#4830). The selection and the purges are covered
# by apps/web/auth/spec/integration/full/interrupted_closures_spec.rb; these
# examples assert what the ADAPTER adds: dry run by default, --confirm and
# --reason threaded through, the report lists each record and its outcome,
# a purge that did not complete exits 1, --json emits the documented
# document, a database or Redis failure exits 1, and --help renders.
RSpec.describe 'customers finish-closures', type: :cli do
  let(:op) { instance_double(Auth::Operations::Customers::FinishClosures) }
  let(:candidate) { { extid: 'ur_closing', email: 'cl***@e***.com', closure_started_at: 1_700_000_000 } }

  def build_result(dry_run:, candidates: [candidate], results: [])
    Auth::Operations::Customers::FinishClosures::Result.new(
      dry_run: dry_run, candidates: candidates, results: results,
    )
  end

  before do
    allow(Auth::Operations::Customers::FinishClosures).to receive(:new).and_return(op)
    allow(op).to receive(:call).and_return(build_result(dry_run: true))
  end

  describe 'dry run by default' do
    it 'constructs the op with dry_run: true, lists the records and exits 0' do
      output = run_cli_command_quietly('customers', 'finish-closures')

      expect(Auth::Operations::Customers::FinishClosures).to have_received(:new)
        .with(dry_run: true, actor: 'cli', reason: nil)
      expect(output[:stdout]).to include('DRY RUN')
      expect(output[:stdout]).to include('ur_closing')
      expect(output[:stdout]).to include('closing since 2023-11-14 22:13 UTC')
      expect(output[:stdout]).to include('1 record(s) would be purged')
      expect(last_exit_code).to eq(0)
    end

    it 'says so when there is nothing to finish' do
      allow(op).to receive(:call).and_return(build_result(dry_run: true, candidates: []))

      output = run_cli_command_quietly('customers', 'finish-closures')

      expect(output[:stdout]).to include('Nothing to finish')
      expect(last_exit_code).to eq(0)
    end
  end

  describe '--confirm' do
    it 'constructs the op with dry_run: false and the reason, reports each purge and exits 0' do
      allow(op).to receive(:call).and_return(
        build_result(dry_run: false, results: [{ extid: 'ur_closing', status: :success, stage: :completed, blockers: [] }]),
      )

      output = run_cli_command_quietly('customers', 'finish-closures', '--confirm', '--reason', 'Ticket 123')

      expect(Auth::Operations::Customers::FinishClosures).to have_received(:new)
        .with(dry_run: false, actor: 'cli', reason: 'Ticket 123')
      expect(output[:stdout]).to include('ur_closing')
      expect(output[:stdout]).to include('-> success')
      expect(output[:stdout]).to include('Purged 1 of 1 record(s).')
      expect(last_exit_code).to eq(0)
    end

    it 'shows the blockers of a refused purge and exits 1' do
      allow(op).to receive(:call).and_return(
        build_result(
          dry_run: false,
          results: [{ extid: 'ur_closing', status: :refused, stage: :preflight, blockers: [{ code: :org_has_members }] }],
        ),
      )

      output = run_cli_command_quietly('customers', 'finish-closures', '--confirm')

      expect(output[:stdout]).to include('-> refused')
      expect(output[:stdout]).to include('org_has_members')
      expect(output[:stdout]).to include('Purged 0 of 1 record(s).')
      expect(last_exit_code).to eq(1)
    end
  end

  describe '--json' do
    it 'emits exactly one JSON document {dry_run, candidates, results}' do
      output  = run_cli_command_quietly('customers', 'finish-closures', '--json')
      payload = JSON.parse(output[:stdout])

      expect(payload.keys).to match_array(%w[dry_run candidates results])
      expect(payload['dry_run']).to be(true)
      expect(payload['candidates']).to eq(
        [{ 'extid' => 'ur_closing', 'email' => 'cl***@e***.com', 'closure_started_at' => 1_700_000_000 }],
      )
      expect(payload['results']).to eq([])
      expect(last_exit_code).to eq(0)
    end
  end

  describe 'when the auth database fails' do
    before do
      allow(op).to receive(:call).and_raise(Sequel::DatabaseConnectionError, 'could not connect to server')
    end

    it 'exits 1 with the reason on stderr' do
      output = run_cli_command_quietly('customers', 'finish-closures', '--confirm')

      expect(last_exit_code).to eq(1)
      expect(output[:stderr]).to include('could not connect to server')
    end

    it 'reports the reason as JSON under --json' do
      output = run_cli_command_quietly('customers', 'finish-closures', '--json')

      expect(last_exit_code).to eq(1)
      expect(JSON.parse(output[:stdout])).to eq('error' => 'Cannot finish closures: could not connect to server')
    end
  end

  describe 'when Redis is unreachable' do
    before do
      allow(op).to receive(:call).and_raise(Redis::CannotConnectError, 'valkey unavailable')
    end

    it 'reports the reason as JSON under --json, exit 1' do
      output = run_cli_command_quietly('customers', 'finish-closures', '--confirm', '--json')

      expect(last_exit_code).to eq(1)
      expect(JSON.parse(output[:stdout])).to eq('error' => 'Cannot finish closures: valkey unavailable')
    end
  end

  describe '--help' do
    it 'renders usage without calling the op' do
      output = run_cli_command_quietly('customers', 'finish-closures', '--help')

      expect(output[:stdout]).to include('bin/ots customers finish-closures [options]')
      expect(op).not_to have_received(:call)
      expect(last_exit_code).to eq(0)
    end
  end
end
