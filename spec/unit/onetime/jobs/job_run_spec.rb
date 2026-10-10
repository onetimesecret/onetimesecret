# spec/unit/onetime/jobs/job_run_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/jobs/job_run'

# Scheduler run records (#4343) against the real test Valkey: what the
# scheduler writes per job and per process, how readers coerce it, and the
# catalog projection the colonel endpoint and `ots scheduler status` share.
#
# Writers are best-effort (a job must never fail because its record could not
# be written); readers raise.
RSpec.describe Onetime::Jobs::JobRun do
  include_context 'with isolated job run records'

  let(:now) { Familia.now.to_i }
  let(:job_class) do
    Class.new do
      def self.name = 'Onetime::Jobs::Scheduled::RecordedJob'
    end
  end

  def raw(job_id) = Familia.dbclient.hgetall(described_class.key(job_id))

  # Familia.dbclient may hand out a different client per call, so a message
  # expectation is set on one client pinned behind the module's own accessor.
  def pinned_client
    @pinned_client ||= Familia.dbclient.tap do |client|
      allow(described_class).to receive(:dbclient).and_return(client)
    end
  end

  describe '.job_id_for' do
    {
      'HeartbeatJob' => 'heartbeat',
      'Onetime::Jobs::Scheduled::Maintenance::ParticipationGCJob' => 'participation_gc',
      'EntitlementMaterializeJob' => 'entitlement_materialize',
      'DlqEmailConsumerJob' => 'dlq_email_consumer',
      'Onetime::Organization' => 'organization',
    }.each do |name, job_id|
      it "maps #{name} to #{job_id}" do
        expect(described_class.job_id_for(name)).to eq(job_id)
      end
    end

    it 'reads a class by its #name, honouring an override' do
      expect(described_class.job_id_for(job_class)).to eq('recorded')
      expect(described_class.job_id_for(Onetime::Jobs::JobRun)).to eq('job_run')
    end

    it 'returns nil when there is no name to derive from' do
      expect(described_class.job_id_for(Class.new)).to be_nil
      expect(described_class.job_id_for(nil)).to be_nil
      expect(described_class.job_id_for('Job')).to be_nil
    end
  end

  describe '.register' do
    it 'writes the documented registration fields' do
      next_time = Time.at(now + 3600)

      expect(described_class.register(job_class, kind: :every, expression: '1h', next_time: next_time)).to be(true)

      expect(raw('recorded')).to include(
        'job_class' => 'Onetime::Jobs::Scheduled::RecordedJob',
        'schedule_kind' => 'every',
        'schedule_expression' => '1h',
        'next_time' => (now + 3600).to_s,
        'scheduler_host' => Socket.gethostname,
        'scheduler_pid' => Process.pid.to_s,
      )
      expect(raw('recorded')['registered_at'].to_i).to be_within(2).of(now)
    end

    it 'clears a stale next_time when none is given' do
      described_class.register(job_class, kind: :cron, expression: '0 * * * *', next_time: Time.at(now + 60))
      described_class.register(job_class, kind: :cron, expression: '0 * * * *', next_time: nil)

      expect(described_class.read('recorded')['next_time']).to be_nil
    end
  end

  describe '.started' do
    it 'marks the run as running and counts it' do
      2.times { described_class.started('recorded') }

      record = described_class.read('recorded')
      expect(record['last_status']).to eq('running')
      expect(record['last_started_at']).to be_within(2).of(now)
      expect(record['run_count']).to eq(2)
    end
  end

  describe '.finished' do
    it 'records a success without touching the error counter' do
      described_class.finished('recorded', status: 'success', duration_ms: 12, next_time: Time.at(now + 60))

      record = described_class.read('recorded')
      expect(record).to include(
        'last_status' => 'success', 'last_duration_ms' => 12,
        'next_time' => now + 60, 'last_error' => nil
      )
      expect(record['last_finished_at']).to be_within(2).of(now)
      expect(record['error_count']).to be_nil
    end

    it 'leaves next_time alone when none is given' do
      described_class.finished('recorded', status: 'success', duration_ms: 1, next_time: Time.at(now + 60))
      described_class.finished('recorded', status: 'success', duration_ms: 1)

      expect(described_class.read('recorded')['next_time']).to eq(now + 60)
    end

    it 'counts an error and truncates its text to MAX_ERROR_LENGTH' do
      described_class.finished('recorded', status: 'error', duration_ms: 3, error: "RuntimeError: #{'x' * 400}")
      described_class.finished('recorded', status: 'error', duration_ms: 3, error: 'RuntimeError: again')

      record = described_class.read('recorded')
      expect(record['error_count']).to eq(2)
      expect(record['last_error']).to eq('RuntimeError: again')

      described_class.finished('recorded', status: 'error', duration_ms: 3, error: 'y' * 400)
      expect(described_class.read('recorded')['last_error'].length).to eq(described_class::MAX_ERROR_LENGTH)
    end

    it 'stores error text with email addresses obscured' do
      described_class.finished('recorded', status: 'error', duration_ms: 1,
        error: 'Delivery failed for alice@example.com: timeout')

      error = described_class.read('recorded')['last_error']
      expect(error).not_to include('alice@example.com')
      expect(error).to start_with('Delivery failed for ').and end_with(': timeout')
    end

    it 'clears the previous error on a later success but keeps the count' do
      described_class.finished('recorded', status: 'error', duration_ms: 1, error: 'boom')
      described_class.finished('recorded', status: 'skipped', duration_ms: 1)

      record = described_class.read('recorded')
      expect(record).to include('last_status' => 'skipped', 'last_error' => nil, 'error_count' => 1)
    end

    it 'refuses an unknown status and writes nothing' do
      expect(described_class.finished('recorded', status: 'bogus', duration_ms: 1)).to be_nil
      expect(described_class.read('recorded')).to be_nil
    end
  end

  describe '.read / .read_many' do
    it 'returns nil for a job with no record' do
      expect(described_class.read('absent')).to be_nil
    end

    it 'coerces integer fields and keeps strings as strings' do
      described_class.register(job_class, kind: :every, expression: '5m', next_time: Time.at(now + 300))
      described_class.started('recorded')

      record = described_class.read('recorded')
      expect(record.values_at('registered_at', 'next_time', 'run_count', 'scheduler_pid')).to all(be_an(Integer))
      expect(record['schedule_expression']).to eq('5m')
    end

    it 'reads several jobs in one pipelined batch' do
      described_class.started('recorded')

      expect(pinned_client).to receive(:pipelined).once.and_call_original
      result = described_class.read_many(%w[recorded absent])

      expect(result.keys).to eq(%w[recorded absent])
      expect(result['recorded']['last_status']).to eq('running')
      expect(result['absent']).to be_nil
    end

    it 'answers an empty batch without a round trip' do
      expect(pinned_client).not_to receive(:pipelined)
      expect(described_class.read_many([])).to eq({})
    end
  end

  describe 'scheduler liveness' do
    it 'reports a scheduler that never started as not alive with nil fields' do
      expect(described_class.scheduler).to eq(
        'alive' => false, 'started_at' => nil, 'heartbeat_at' => nil,
        'host' => nil, 'pid' => nil, 'job_count' => nil
      )
    end

    it 'records the boot and reports it alive' do
      described_class.scheduler_started!(job_count: 16, started_at: now - 5)

      expect(described_class.scheduler).to include(
        'alive' => true, 'started_at' => now - 5, 'host' => Socket.gethostname,
        'pid' => Process.pid, 'job_count' => 16
      )
    end

    it 'reports alive: false once the heartbeat is older than ALIVE_WINDOW' do
      described_class.scheduler_started!(job_count: 1)
      Familia.dbclient.hset(described_class::SCHEDULER_KEY, 'heartbeat_at',
        (now - described_class::ALIVE_WINDOW - 1).to_s)

      expect(described_class.scheduler['alive']).to be(false)

      described_class.scheduler_heartbeat!
      expect(described_class.scheduler['alive']).to be(true)
    end
  end

  describe '.catalog' do
    let(:entries) do
      [
        { 'job_id' => 'zeta', 'job_class' => 'ZetaJob', 'group' => 'maintenance' },
        { 'job_id' => 'beta', 'job_class' => 'BetaJob', 'group' => 'scheduled' },
        { 'job_id' => 'alpha', 'job_class' => 'AlphaJob', 'group' => 'scheduled' },
      ]
    end

    def row(catalog, job_id) = catalog['jobs'].find { |entry| entry['job_id'] == job_id }

    it 'sorts scheduled jobs before maintenance jobs, then by id' do
      expect(described_class.catalog(entries)['jobs'].map { |entry| entry['job_id'] }).to eq(%w[alpha beta zeta])
    end

    it 'reports a job that never ran as never/unknown with zero counts' do
      expect(row(described_class.catalog(entries), 'alpha')).to eq(
        'job_id' => 'alpha', 'job_class' => 'AlphaJob', 'group' => 'scheduled', 'state' => 'unknown',
        'schedule_kind' => nil, 'schedule_expression' => nil, 'next_time' => nil, 'registered_at' => nil,
        'last_status' => 'never', 'last_started_at' => nil, 'last_finished_at' => nil,
        'last_duration_ms' => nil, 'last_error' => nil, 'run_count' => 0, 'error_count' => 0
      )
    end

    it 'derives state from registered_at against the scheduler boot' do
      alpha = Class.new { def self.name = 'AlphaJob' }
      zeta  = Class.new { def self.name = 'ZetaJob' }
      described_class.register(zeta, kind: :cron, expression: '0 4 * * *', next_time: Time.at(now + 60))
      allow(Familia).to receive(:now).and_return(now + 10)
      described_class.scheduler_started!(job_count: 1, started_at: now + 10)
      described_class.register(alpha, kind: :every, expression: '1m', next_time: Time.at(now + 70))

      catalog = described_class.catalog(entries)
      expect(row(catalog, 'alpha')).to include('state' => 'scheduled', 'next_time' => now + 70)
      # Registered by an earlier boot: no next run is claimed for it.
      expect(row(catalog, 'zeta')).to include('state' => 'not_scheduled', 'next_time' => nil)
      expect(row(catalog, 'beta')['state']).to eq('not_scheduled')
      expect(catalog['scheduler']).to include('alive' => true, 'job_count' => 1)
    end

    it 'reads every job and the scheduler record in one round trip' do
      expect(pinned_client).to receive(:pipelined).once.and_call_original
      described_class.catalog(entries)
    end
  end

  describe 'failure handling' do
    let(:logger) { instance_double(SemanticLogger::Logger, warn: nil) }

    before do
      allow(described_class).to receive(:dbclient).and_raise(Redis::CannotConnectError, 'down')
      allow(Onetime).to receive(:get_logger).with('Scheduler').and_return(logger)
    end

    it 'swallows a datastore failure in every writer, returning nil' do
      results = [
        described_class.register(job_class, kind: :every, expression: '1h'),
        described_class.started('recorded'),
        described_class.finished('recorded', status: 'success', duration_ms: 1),
        described_class.scheduler_started!(job_count: 1),
        described_class.scheduler_heartbeat!,
      ]

      expect(results).to all(be_nil)
      expect(logger).to have_received(:warn).with(/\[JobRun\] .* failed .*Redis::CannotConnectError/).exactly(5).times
    end

    it 'lets a reader raise' do
      expect { described_class.read('recorded') }.to raise_error(Redis::CannotConnectError)
      expect { described_class.catalog([]) }.to raise_error(Redis::CannotConnectError)
    end
  end
end
