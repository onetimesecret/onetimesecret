# apps/api/colonel/spec/logic/colonel/list_jobs_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'
# Referenced by name below before anything calls Registry.load_all!, so it must
# not depend on an earlier spec having loaded it (order-dependent NameError).
require 'onetime/jobs/scheduled/heartbeat_job'

# GET /api/colonel/jobs (#4343): the scheduler catalog. These pin the adapter's
# own job — the role gate, one row per registered job class, the state and
# never-ran defaults the console renders, and the pagination envelope — against
# real run records in an isolated key namespace.
RSpec.describe ColonelAPI::Logic::Colonel::ListJobs do
  include_context 'with isolated job run records'

  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel',
      role: 'colonel', verified?: true, anonymous?: false)
  end

  let(:customer) do
    instance_double(Onetime::Customer,
      objid: 'cust_plain', extid: 'ur_plain',
      role: 'customer', verified?: true, anonymous?: false)
  end

  let(:registry_ids) do
    Onetime::Jobs::Registry.load_all!
    Onetime::Jobs::Registry.entries.map { |entry| entry['job_id'] }
  end

  def strategy_result_for(user)
    double('StrategyResult', session: {}, user: user,
      auth_method: 'sessionauth', metadata: {})
  end

  def logic_for(user = colonel, params = {})
    described_class.new(strategy_result_for(user), params)
  end

  def run(params = {})
    logic = logic_for(colonel, params)
    logic.raise_concerns
    logic.process
  end

  def row(result, job_id) = result[:details][:jobs].find { |entry| entry['job_id'] == job_id }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
  end

  it 'declares the colonelJobs response schema' do
    expect(described_class::SCHEMAS).to eq(response: 'colonelJobs')
  end

  it 'rejects a non-colonel' do
    expect { logic_for(customer).raise_concerns }.to raise_error(Onetime::Forbidden)
  end

  it 'returns one row for every registered job class' do
    result = run

    expect(result[:details][:jobs].map { |entry| entry['job_id'] }).to match_array(registry_ids)
    expect(result[:details][:pagination][:total_count]).to eq(registry_ids.size)
  end

  it 'reports a job with no record as never run, state unknown, when no scheduler has started' do
    result = run

    expect(row(result, 'heartbeat')).to include(
      'job_class' => 'Onetime::Jobs::Scheduled::HeartbeatJob', 'group' => 'scheduled',
      'state' => 'unknown', 'last_status' => 'never', 'last_error' => nil,
      'run_count' => 0, 'error_count' => 0, 'next_time' => nil
    )
    expect(result[:record][:scheduler]).to eq(
      'alive' => false, 'started_at' => nil, 'heartbeat_at' => nil,
      'host' => nil, 'pid' => nil, 'job_count' => nil
    )
  end

  it 'reports a job registered by the current scheduler boot as scheduled, and the rest as not_scheduled' do
    started_at = Familia.now.to_i
    Onetime::Jobs::JobRun.scheduler_started!(job_count: 1, started_at: started_at)
    Onetime::Jobs::JobRun.register(Onetime::Jobs::Scheduled::HeartbeatJob,
      kind: :every, expression: '1m', next_time: Time.at(started_at + 60))
    Onetime::Jobs::JobRun.finished('heartbeat', status: 'error', duration_ms: 7, error: 'RuntimeError: boom')

    result = run

    expect(row(result, 'heartbeat')).to include(
      'state' => 'scheduled', 'schedule_kind' => 'every', 'schedule_expression' => '1m',
      'next_time' => started_at + 60, 'last_status' => 'error',
      'last_error' => 'RuntimeError: boom', 'error_count' => 1, 'last_duration_ms' => 7
    )
    expect(row(result, 'phantom_cleanup')['state']).to eq('not_scheduled')
    expect(result[:record][:scheduler]).to include('alive' => true, 'job_count' => 1)
  end

  it 'lists scheduled jobs before maintenance jobs' do
    groups = run[:details][:jobs].map { |entry| entry['group'] }

    expect(groups).to eq(groups.sort_by { |group| group == 'scheduled' ? 0 : 1 })
  end

  describe 'pagination' do
    it 'returns the envelope keys' do
      expect(run[:details][:pagination].keys).to eq(%i[page per_page total_count total_pages])
    end

    it 'pages through the catalog' do
      all_ids = run('per_page' => '100')[:details][:jobs].map { |entry| entry['job_id'] }
      result  = run('page' => '2', 'per_page' => '5')

      expect(result[:details][:jobs].map { |entry| entry['job_id'] }).to eq(all_ids[5, 5])
      expect(result[:details][:pagination]).to eq(
        page: 2, per_page: 5, total_count: registry_ids.size,
        total_pages: (registry_ids.size / 5.0).ceil
      )
    end

    it 'clamps per_page to 100 and falls back to 50 for a non-positive value' do
      expect(run('per_page' => '500')[:details][:pagination][:per_page]).to eq(100)
      expect(run('per_page' => '0')[:details][:pagination][:per_page]).to eq(50)
    end

    it 'answers an empty page past the end' do
      expect(run('page' => '99')[:details][:jobs]).to eq([])
    end
  end
end
