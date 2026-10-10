# apps/api/colonel/spec/logic/colonel/list_chores_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# GET /api/colonel/chores (#4343): the chore allowlist with each chore's last
# console run. Pins the role gate, the row shape the console schema
# (colonelChores) expects, the never-ran defaults, the last-run merge against
# real run records in an isolated key namespace, and the pagination envelope.
RSpec.describe ColonelAPI::Logic::Colonel::ListChores do
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

  def row(result, id) = result[:details][:chores].find { |entry| entry['id'] == id }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Onetime.billing_config).to receive(:enabled?).and_return(false)
  end

  it 'declares the colonelChores response schema' do
    expect(described_class::SCHEMAS).to eq(response: 'colonelChores')
  end

  it 'rejects a non-colonel' do
    expect { logic_for(customer).raise_concerns }.to raise_error(Onetime::Forbidden)
  end

  it 'lists exactly the runnable catalog, without the excluded vhost cleanup' do
    ids = run[:details][:chores].map { |entry| entry['id'] }

    expect(ids).to eq(Onetime::Operations::Chores::Catalog.all.map(&:id))
    expect(ids).not_to include('housekeeping.custom_domain.remove_orphaned_approximated_vhosts')
  end

  it 'answers the contract row for a chore that has never run' do
    expect(row(run, 'housekeeping.customer.reserialize_fields')).to eq(
      'id' => 'housekeeping.customer.reserialize_fields',
      'kind' => 'housekeeping',
      'model' => 'Onetime::Customer',
      'chores' => ['reserialize_fields'],
      'supports_dry_run' => false,
      'cli' => 'bin/ots housekeeping run Onetime::Customer reserialize_fields',
      'last_status' => 'never',
      'last_started_at' => nil,
      'last_finished_at' => nil,
      'last_duration_ms' => nil,
      'last_error' => nil,
      'run_count' => 0,
    )
  end

  it 'merges the last console run from its chore.<id> run record' do
    id = 'housekeeping.organization.standardize_planid'
    Onetime::Jobs::JobRun.started("chore.#{id}")
    Onetime::Jobs::JobRun.finished("chore.#{id}", status: 'error', duration_ms: 1234, error: 'boom for alice@example.com')

    chore = row(run, id)

    expect(chore).to include('last_status' => 'error', 'last_duration_ms' => 1234, 'run_count' => 1)
    expect(chore['last_started_at']).to be_a(Integer)
    expect(chore['last_finished_at']).to be_a(Integer)
    expect(chore['last_error']).to start_with('boom for ')
    expect(chore['last_error']).not_to include('alice@example.com')
  end

  it 'lists the entitlement run, with a dry run, when billing is enabled' do
    allow(Onetime.billing_config).to receive(:enabled?).and_return(true)

    expect(row(run, 'entitlement_materialize')).to include(
      'kind' => 'billing', 'model' => 'Onetime::Organization', 'chores' => [], 'supports_dry_run' => true,
    )
  end

  it 'answers the list envelope with pagination' do
    result = run

    expect(result[:record]).to eq({})
    expect(result[:details][:pagination]).to eq(page: 1, per_page: 50, total_count: 7, total_pages: 1)
  end

  it 'pages and clamps per_page to 100' do
    expect(run('per_page' => '1000')[:details][:pagination][:per_page]).to eq(100)

    second = run('page' => '2', 'per_page' => '3')
    expect(second[:details][:chores].size).to eq(3)
    expect(second[:details][:pagination]).to include(page: 2, total_pages: 3)
  end
end
