# spec/cli/customers_sync_auth_accounts_command_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

require 'sequel'
require 'auth/database'
require 'onetime/auth_config'
require 'onetime/cli/customers/sync_auth_accounts_command'

# CLI-layer coverage for the one rule #4819 added to the sweep: a customer
# record whose account closure started and did not finish (Customer#closing?)
# is never given a new, live accounts row. The closed row used to keep the
# sweep off such a record; closure deletes the row now, so the record itself
# has to say so. The fixture is the smallest one the rule needs: an in-memory
# accounts table and two customers, one migrating from simple mode, one left
# behind by an interrupted closure.
RSpec.describe 'customers sync-auth-accounts', type: :cli do
  let(:db) do
    Sequel.sqlite.tap do |db|
      db.create_table(:accounts) do
        primary_key :id
        String :email, null: false
        String :external_id
        Integer :status_id, null: false
        Time :created_at
        Time :updated_at
      end
    end
  end

  let(:migrating) { customer_double(email: 'simple-mode@example.com', extid: 'ur_migrating') }
  let(:interrupted) do
    customer_double(email: 'closed@example.com', extid: 'ur_interrupted', closing: true)
  end

  def customer_double(email:, extid:, closing: false)
    double(
      "Customer #{extid}",
      custid: email,
      email: email,
      extid: extid,
      anonymous?: false,
      global?: false,
      verified?: true,
      closing?: closing,
    )
  end

  before do
    allow(Onetime).to receive(:auth_config).and_return(double('auth config', full_enabled?: true))
    allow(Auth::Database).to receive(:connection).and_return(db)
    allow(Onetime::Customer).to receive(:instances)
      .and_return(double('instances', all: %w[objid-migrating objid-interrupted]))
    allow(Onetime::Customer).to receive(:load_multi)
      .with(%w[objid-migrating objid-interrupted])
      .and_return([migrating, interrupted])
  end

  it 'previews a row for the migrating customer and none for the interrupted closure' do
    output = run_cli_command_quietly('customers', 'sync-auth-accounts')

    expect(output[:stdout]).to include('DRY RUN MODE')
    expect(output[:stdout]).to include('Skipped (closing):   1')
    expect(output[:stdout]).to include('Created:             1')
    expect(db[:accounts].count).to eq(0)
    expect(last_exit_code).to eq(0)
  end

  it 'creates the migrating row under --run and never one for the interrupted closure' do
    output = run_cli_command_quietly('customers', 'sync-auth-accounts', '--run')

    expect(db[:accounts].select_map(:external_id)).to eq(['ur_migrating'])
    expect(db[:accounts].where(email: 'closed@example.com').count).to eq(0)
    expect(output[:stdout]).to include('Skipped (closing):   1')
    expect(output[:stdout]).to include('bin/ots customers purge ID')
    expect(last_exit_code).to eq(0)
  end

  it 'names the skipped record under --verbose, with the address obscured' do
    output = run_cli_command_quietly('customers', 'sync-auth-accounts', '--verbose')

    expect(output[:stdout]).to include('Skipping interrupted closure: cl***@')
    expect(output[:stdout]).not_to include('closed@example.com')
  end
end
