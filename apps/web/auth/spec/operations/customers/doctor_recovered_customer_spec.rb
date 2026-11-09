# apps/web/auth/spec/operations/customers/doctor_recovered_customer_spec.rb
#
# frozen_string_literal: true

# Unit tests for the :recovered_customer_unverified doctor check.
#
# SyncSession#recreate_customer fails closed: when its provenance lookup
# raises it recreates the Customer unverified with provisioning_origin
# 'login_recovery', while the accounts row stays Verified. This check makes
# that record visible. It reports at :medium and never repairs, because a
# repair would widen access on the strength of a lookup that failed.
#
# Mirrors doctor_sso_verified_spec.rb: the private check is exercised directly.
#
# Run: tests/lanes/run unit --only apps/web/auth/spec/operations/customers/doctor_recovered_customer_spec.rb

require 'spec_helper'
require 'auth/database'
require 'auth/operations/customers/doctor'

RSpec.describe Auth::Operations::Customers::Doctor do
  let(:issues) { [] }

  let(:verified)            { false }
  let(:provisioning_origin) { 'login_recovery' }
  let(:account_status)      { Auth::AccountStatuses::VERIFIED }
  let(:account_row)         { { id: 42, email: 'rec@example.com', status_id: account_status } }

  let(:customer) do
    double(
      'Customer',
      email: 'rec@example.com',
      objid: 'obj_r',
      extid: 'ur_r',
      verified?: verified,
      provisioning_origin: provisioning_origin,
      closing?: false,
    )
  end

  let(:by_external_id) { double('by_external_id') }
  let(:accounts)       { double('accounts') }
  let(:db)             { double('db') }

  before do
    allow(OT).to receive(:le)
    allow(Auth::Database).to receive(:connection).and_return(db)
    allow(db).to receive(:[]).with(:accounts).and_return(accounts)
    allow(accounts).to receive(:where).with(external_id: 'ur_r').and_return(by_external_id)
    allow(by_external_id).to receive(:select).with(*described_class::AUTH_ACCOUNT_COLUMNS).and_return(by_external_id)
    allow(by_external_id).to receive(:first).and_return(account_row)
    allow(Auth::Operations::SetCustomerVerification).to receive(:new)
  end

  def run(repair: false)
    described_class.new(customer: customer, repair: repair, actor: 'cli')
      .send(:check_recovered_customer_unverified, issues)
  end

  it 'reports a medium, non-repairable issue', :aggregate_failures do
    run

    expect(issues.size).to eq(1)
    expect(issues.first).to include(
      check: :recovered_customer_unverified,
      severity: :medium,
      repairable: false,
    )
  end

  it 'never writes, even under repair: true' do
    run(repair: true)

    expect(Auth::Operations::SetCustomerVerification).not_to have_received(:new)
  end

  context 'when the customer is verified' do
    let(:verified) { true }

    it 'reports nothing' do
      run
      expect(issues).to be_empty
    end
  end

  context 'when the customer was not recreated at login' do
    let(:provisioning_origin) { 'canonical_signup' }

    it 'reports nothing' do
      run
      expect(issues).to be_empty
    end
  end

  context 'when the auth account is not Verified' do
    let(:account_status) { Auth::AccountStatuses::UNVERIFIED }

    it 'reports nothing' do
      run
      expect(issues).to be_empty
    end
  end

  context 'when there is no auth account row' do
    let(:account_row) { nil }

    it 'reports nothing' do
      run
      expect(issues).to be_empty
    end
  end

  # Reported rather than read as "no row" (doctor_auth_account_unreadable_spec.rb).
  it 'never aborts the sweep when the lookup raises, and says it did not check', :aggregate_failures do
    allow(by_external_id).to receive(:first).and_raise(Sequel::DatabaseError, 'down')

    expect { run }.not_to raise_error
    expect(issues.map { |issue| issue[:check] }).to eq([:auth_account_unreadable])
    expect(issues.first[:checks_not_run]).to eq([:recovered_customer_unverified])
  end
end
