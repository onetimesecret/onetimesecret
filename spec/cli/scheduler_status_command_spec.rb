# spec/cli/scheduler_status_command_spec.rb
#
# frozen_string_literal: true

# `ots scheduler status` (#4343). The command is thin over
# Onetime::Jobs::JobRun.catalog — the projection GET /api/colonel/jobs serves —
# so these cover the CLI's own job: the liveness line, the table, the JSON
# pass-through, format validation, and coexistence with the `ots scheduler`
# daemon command under the same name.
#
# Run: tests/lanes/run --only spec/cli/scheduler_status_command_spec.rb

require_relative 'cli_spec_helper'

RSpec.describe 'scheduler status CLI command', type: :cli do
  let(:now) { 1_800_000_000 }

  let(:scheduler) do
    {
      'alive' => true, 'started_at' => now - 3600, 'heartbeat_at' => now - 12,
      'host' => 'sched-1', 'pid' => 4242, 'job_count' => 15
    }
  end

  let(:jobs) do
    [
      {
        'job_id' => 'heartbeat', 'job_class' => 'Onetime::Jobs::Scheduled::HeartbeatJob',
        'group' => 'scheduled', 'state' => 'scheduled', 'schedule_kind' => 'every',
        'schedule_expression' => '1m', 'next_time' => now + 48, 'registered_at' => now - 3600,
        'last_status' => 'error', 'last_started_at' => now - 12, 'last_finished_at' => now - 12,
        'last_duration_ms' => 3, 'last_error' => "RuntimeError: #{'x' * 100}",
        'run_count' => 60, 'error_count' => 1
      },
      {
        'job_id' => 'phantom_cleanup', 'job_class' => 'Onetime::Jobs::Scheduled::Maintenance::PhantomCleanupJob',
        'group' => 'maintenance', 'state' => 'not_scheduled', 'schedule_kind' => nil,
        'schedule_expression' => nil, 'next_time' => nil, 'registered_at' => nil,
        'last_status' => 'never', 'last_started_at' => nil, 'last_finished_at' => nil,
        'last_duration_ms' => nil, 'last_error' => nil, 'run_count' => 0, 'error_count' => 0
      },
    ]
  end

  let(:catalog) { { 'scheduler' => scheduler, 'jobs' => jobs } }

  before do
    mock_ot_boot
    allow(Familia).to receive(:now).and_return(now)
    allow(Onetime::Jobs::JobRun).to receive(:catalog).and_return(catalog)
  end

  it 'registers beside the scheduler daemon command without replacing it' do
    expect(Onetime::CLI.get(%w[scheduler]).command).to eq(Onetime::CLI::SchedulerCommand)
    expect(Onetime::CLI.get(%w[scheduler status]).command).to eq(Onetime::CLI::Scheduler::StatusCommand)
  end

  it 'reads the catalog for the registry entries' do
    run_cli_command_quietly('scheduler', 'status')

    expect(Onetime::Jobs::JobRun).to have_received(:catalog).with(Onetime::Jobs::Registry.entries)
  end

  it 'prints the liveness line and one table row per job' do
    output = run_cli_command_quietly('scheduler', 'status')[:stdout]

    expect(output).to include('Scheduler: alive (sched-1 pid 4242, heartbeat 12s ago, 15 job(s))')
    expect(output).to include('Job', 'State', 'Last status', 'Last run (UTC)', 'Next (UTC)', 'Runs', 'Error')
    heartbeat = output.lines.find { |line| line.start_with?('heartbeat ') }
    expect(heartbeat).to include('scheduled', 'error', Time.at(now - 12).utc.strftime('%Y-%m-%d %H:%M:%S'), '60')
    expect(heartbeat).to include("RuntimeError: #{'x' * 43}...")
    phantom = output.lines.find { |line| line.start_with?('phantom_cleanup ') }
    expect(phantom).to include('not_scheduled', 'never', '-')
  end

  it 'says when the scheduler heartbeat is stale' do
    scheduler.merge!('alive' => false, 'heartbeat_at' => now - 600)

    output = run_cli_command_quietly('scheduler', 'status')[:stdout]

    expect(output).to include('Scheduler: NOT alive (sched-1 pid 4242, last heartbeat 10m ago)')
  end

  it 'says when no scheduler has ever started' do
    scheduler.merge!('alive' => false, 'heartbeat_at' => nil, 'started_at' => nil, 'host' => nil, 'pid' => nil)

    output = run_cli_command_quietly('scheduler', 'status')[:stdout]

    expect(output).to include('Scheduler: not seen')
  end

  it 'prints the catalog unchanged as JSON' do
    output = run_cli_command_quietly('scheduler', 'status', '--format', 'json')[:stdout]

    expect(JSON.parse(output)).to eq(catalog)
  end

  it 'rejects an unknown format before booting' do
    output = run_cli_command_quietly('scheduler', 'status', '--format', 'csv')

    expect(last_exit_code).to eq(1)
    expect(output[:stderr]).to include("Unknown format 'csv'")
    expect(Onetime::Jobs::JobRun).not_to have_received(:catalog)
  end
end
