# apps/web/auth/spec/operations/teardown_account_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'auth/operations/teardown_account'

RSpec.describe Auth::Operations::TeardownAccount do
  let(:customer) { double('Customer', extid: 'ur_target', custid: 'target@example.com') }
  let(:customer_deleter) { instance_double(Auth::Operations::DestroyCustomerRecord, call: true) }
  let(:admin_revoker) { instance_double(Onetime::Operations::Sessions::RevokeAllForCustomer, call: nil) }
  let(:self_revoker) do
    instance_double(Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent, call: nil)
  end

  before do
    allow(Auth::Operations::DestroyCustomerRecord).to receive(:new).and_return(customer_deleter)
    allow(Onetime::Operations::Sessions::RevokeAllForCustomer).to receive(:new).and_return(admin_revoker)
    allow(Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent)
      .to receive(:new).and_return(self_revoker)
    allow(Auth::Operations::RemoveAuthenticationData).to receive(:call)
      .and_return(success: true, account_id: 42)
  end

  it 'permanently deletes a simple-mode self-service account without Colonel audit operations' do
    allow(Onetime.auth_config).to receive(:full_enabled?).and_return(false)

    expect(self_revoker).to receive(:call).ordered
    expect(customer_deleter).to receive(:call).ordered.and_return(true)

    result = described_class.new(customer: customer).call

    expect(result.status).to eq(:success)
    expect(Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent)
      .to have_received(:new).with(customer: customer, except_session_id: nil)
    expect(Onetime::Operations::Sessions::RevokeAllForCustomer).not_to have_received(:new)
    expect(Auth::Operations::RemoveAuthenticationData).not_to have_received(:call)
  end

  it 'revokes sessions, closes SQL credentials, then deletes Redis state for an admin purge' do
    allow(Onetime.auth_config).to receive(:full_enabled?).and_return(true)

    expect(admin_revoker).to receive(:call).ordered
    expect(Auth::Operations::RemoveAuthenticationData).to receive(:call)
      .with(
        extid: 'ur_target',
        db: nil,
        allow_missing: true,
        revoke_sessions: false,
        retain_account: true,
      ).ordered
      .and_return(success: true, account_id: 42)
    expect(customer_deleter).to receive(:call).ordered.and_return(true)

    result = described_class.new(customer: customer, actor: 'ur_colonel', reason: 'request').call

    expect(result.status).to eq(:success)
    expect(result.account_id).to eq(42)
    expect(Onetime::Operations::Sessions::RevokeAllForCustomer).to have_received(:new).with(
      customer: customer,
      actor: 'ur_colonel',
      reason: 'request',
    )
  end

  it 'uses the Rodauth transaction database for self-service teardown' do
    allow(Onetime.auth_config).to receive(:full_enabled?).and_return(true)
    account = { id: 42, external_id: 'ur_target' }
    db      = double('Auth database')
    allow(Onetime::Customer).to receive(:find_by_extid).with('ur_target').and_return(customer)

    result = described_class.new(account: account, db: db).call

    expect(result.status).to eq(:success)
    expect(result.account_id).to eq(42)
    expect(Auth::Operations::RemoveAuthenticationData).to have_received(:call).with(
      extid: 'ur_target',
      db: db,
      allow_missing: true,
      revoke_sessions: false,
      retain_account: true,
    )
    expect(Auth::Operations::DestroyCustomerRecord).to have_received(:new).with(customer: customer)
  end

  it 'scrubs SQL credentials when the account has no resolvable Redis customer' do
    allow(Onetime.auth_config).to receive(:full_enabled?).and_return(true)
    account = { id: 42, external_id: 'ur_missing', email: 'missing@example.com' }
    db      = double('Auth database')
    allow(Onetime::Customer).to receive(:find_by_extid).with('ur_missing').and_return(nil)
    allow(Onetime::Customer).to receive(:find_by_email).with('missing@example.com').and_return(nil)

    result = described_class.new(account: account, db: db).call

    expect(result.status).to eq(:success)
    expect(Auth::Operations::RemoveAuthenticationData).to have_received(:call).with(
      extid: 'ur_missing',
      db: db,
      allow_missing: true,
      revoke_sessions: false,
      retain_account: true,
    )
    expect(customer_deleter).not_to have_received(:call)
  end

  it 'does not delete Redis state when closing SQL credentials fails' do
    allow(Onetime.auth_config).to receive(:full_enabled?).and_return(true)
    allow(Auth::Operations::RemoveAuthenticationData).to receive(:call)
      .and_return(success: false, error: 'database unavailable')

    expect { described_class.new(customer: customer).call }
      .to raise_error(Onetime::Problem, /database unavailable/)

    expect(customer_deleter).not_to have_received(:call)
  end
end
