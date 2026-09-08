# apps/api/colonel/spec/logic/colonel/list_users_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'
require 'auth/operations/customers/list'

# Adapter-layer coverage only. Enumeration, search and the authdb fallback
# are covered by apps/web/auth/spec/operations/customers/list_spec.rb. These
# examples assert what THIS adapter owns: param plumbing into the op, the
# per-row shape, and the details envelope (pagination + orphaned_accounts,
# which must be present on every response so the client schema is stable
# across auth modes).
RSpec.describe ColonelAPI::Logic::Colonel::ListUsers do
  let(:op) { instance_double(Auth::Operations::Customers::List) }

  let(:colonel) do
    instance_double(
      Onetime::Customer,
      objid: 'cust_colonel',
      extid: 'ur_colonel',
      role: 'colonel',
      verified?: true,
      anonymous?: false,
    )
  end

  let(:strategy_result) do
    double(
      'StrategyResult',
      session: {},
      user: colonel,
      auth_method: 'sessionauth',
      metadata: {},
    )
  end

  let(:row) do
    instance_double(
      Onetime::Customer,
      anonymous?: false,
      user_id: 'uid1',
      extid: 'ur_bob',
      email: 'bob@example.com',
      role: 'customer',
      verified?: true,
      suspended?: false,
      created: 1_700_000_000,
      last_login: nil,
      planid: 'basic',
      organization_instances: [],
      secrets_active: 2,
      secrets_created: 5,
      secrets_shared: 1,
    )
  end

  let(:orphan) do
    {
      email: 'ghost@example.com',
      account_id: 42,
      external_id: nil,
      status: 'verified',
      created_at: 1_700_000_000,
    }
  end

  def op_result(customers: [row], orphaned_accounts: [])
    Auth::Operations::Customers::List::Result.new(
      customers: customers,
      total_count: customers.size,
      page: 1,
      per_page: 50,
      total_pages: 1,
      role: nil,
      capped: false,
      orphaned_accounts: orphaned_accounts,
    )
  end

  def logic_for(params = {})
    described_class.new(strategy_result, params)
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(Auth::Operations::Customers::List).to receive(:new).and_return(op)
  end

  it 'passes page / per_page / role / search through to the op' do
    allow(op).to receive(:call).and_return(op_result)

    logic = logic_for('page' => '2', 'per_page' => '25', 'role' => 'admin', 'search' => 'bob@')
    logic.raise_concerns
    logic.process

    expect(Auth::Operations::Customers::List).to have_received(:new)
      .with(page: 2, per_page: 25, role: 'admin', search: 'bob@')
  end

  it 'emits the row shape, pagination and an always-present orphaned_accounts' do
    allow(op).to receive(:call).and_return(op_result)

    logic = logic_for
    logic.raise_concerns
    data = logic.process

    expect(data[:details][:users].map { |u| u[:extid] }).to eq(['ur_bob'])
    expect(data[:details][:users].first).to include(email: 'bob@example.com', secrets_count: 2)
    expect(data[:details][:pagination]).to include(total_count: 1, total_pages: 1, capped: false)
    expect(data[:details]).to have_key(:orphaned_accounts)
    expect(data[:details][:orphaned_accounts]).to eq([])
  end

  it 'passes the op orphaned_accounts through unchanged, outside the user count' do
    allow(op).to receive(:call).and_return(op_result(customers: [], orphaned_accounts: [orphan]))

    logic = logic_for('search' => 'ghost@example.com')
    logic.raise_concerns
    data = logic.process

    expect(data[:details][:users]).to eq([])
    expect(data[:details][:pagination][:total_count]).to eq(0)
    expect(data[:details][:orphaned_accounts]).to eq([orphan])
  end
end
