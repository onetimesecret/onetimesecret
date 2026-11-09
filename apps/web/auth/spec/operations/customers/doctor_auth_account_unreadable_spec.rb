# apps/web/auth/spec/operations/customers/doctor_auth_account_unreadable_spec.rb
#
# frozen_string_literal: true

# The cross-store checks of Auth::Operations::Customers::Doctor when the
# shared accounts-row read (memoized `auth_account`) raises.
#
# AUTH_ACCOUNT_COLUMNS names `login` and the migration 015 verification
# columns, so on a schema-014 database the SELECT raises PG::UndefinedColumn
# (a Sequel::DatabaseError). Auth::Migrator.run_if_needed lets a process boot
# at 014 while another one holds the migration lock. These checks read a
# failed read as "no accounts row" and returned without a finding, so a
# `doctor --all` run printed a clean report for a customer with a critical
# :auth_email_drift. Each check that needs the row now names itself on one
# :auth_account_unreadable issue per customer.
#
# Two neighbouring states stay silent: simple mode (no auth database) and a
# missing accounts row (a provisioning gap that `bin/ots customers
# sync-auth-accounts` owns).
#
# The checks are private and are exercised directly, as in the other doctor
# specs, so a failure names the check.
#
# Run: tests/lanes/run unit --only apps/web/auth/spec/operations/customers/doctor_auth_account_unreadable_spec.rb

require 'spec_helper'
require 'auth/database'
require 'auth/operations/customers/doctor'

RSpec.describe Auth::Operations::Customers::Doctor, 'with an unreadable accounts row' do
  let(:issues)   { [] }
  let(:repaired) { [] }

  let(:email)               { 'live@example.com' }
  let(:verified)            { true }
  let(:provisioning_origin) { 'canonical_signup' }

  let(:customer) do
    double(
      'Customer',
      email: email,
      objid: 'obj_c',
      extid: 'ur_c',
      obscure_email: 'li***@e***.com',
      verified?: verified,
      mailbox_verified?: verified,
      verified_by: verified ? 'email' : nil,
      verification_hold: nil,
      provisioning_origin: provisioning_origin,
      closing?: false,
    )
  end

  let(:by_external_id) { double('by_external_id') }
  let(:accounts)       { double('accounts') }
  let(:db)             { double('db') }

  let(:schema_014_error) do
    Sequel::DatabaseError.new('PG::UndefinedColumn: ERROR:  column "login" does not exist')
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:le)

    allow(Auth::Database).to receive(:connection).and_return(db)
    allow(db).to receive(:[]).with(:accounts).and_return(accounts)
    allow(accounts).to receive(:where).with(external_id: 'ur_c').and_return(by_external_id)
    allow(by_external_id).to receive(:select).with(*described_class::AUTH_ACCOUNT_COLUMNS).and_return(by_external_id)
    allow(by_external_id).to receive(:first).and_raise(schema_014_error)
  end

  def doctor
    @doctor ||= described_class.new(customer: customer, actor: 'cli')
  end

  def unreadable_issues
    issues.select { |issue| issue[:check] == :auth_account_unreadable }
  end

  shared_examples 'a check that reports the unreadable row' do |check_name|
    it "names #{check_name} on a critical, non-repairable :auth_account_unreadable issue" do
      expect { run_check }.not_to raise_error

      expect(issues.size).to eq(1)
      expect(unreadable_issues.first).to include(
        severity: :critical,
        repairable: false,
        error: 'Sequel::DatabaseError',
        checks_not_run: [check_name],
      )
      expect(unreadable_issues.first[:message]).to include(check_name.to_s)
    end
  end

  describe ':auth_email_drift' do
    def run_check = doctor.send(:check_auth_email_drift, issues, repaired)

    include_examples 'a check that reports the unreadable row', :auth_email_drift

    # The early return on a nil handle used to come before the row read, so
    # a connection that could not be built was silent here even after the
    # read itself reported.
    it 'reports a connection that cannot be built' do
      allow(Auth::Database).to receive(:connection).and_raise(Sequel::DatabaseConnectionError, 'down')

      run_check

      expect(unreadable_issues.first).to include(
        error: 'Sequel::DatabaseConnectionError',
        checks_not_run: [:auth_email_drift],
      )
    end

    context 'when the Customer has no email' do
      let(:email) { '' }

      it 'reports nothing and does not read the row: the check does not apply' do
        run_check

        expect(issues).to be_empty
        expect(by_external_id).not_to have_received(:first)
      end
    end
  end

  describe ':auth_email_not_canonical' do
    def run_check = doctor.send(:check_auth_email_canonical, issues)

    include_examples 'a check that reports the unreadable row', :auth_email_not_canonical
  end

  describe ':auth_login_*' do
    def run_check = doctor.send(:check_auth_login_link, issues)

    include_examples 'a check that reports the unreadable row', :auth_login_link
  end

  describe ':sso_customer_unverified' do
    def run_check = doctor.send(:check_sso_customer_unverified, issues, repaired)

    let(:verified)            { false }
    let(:provisioning_origin) { 'sso_jit' }

    include_examples 'a check that reports the unreadable row', :sso_customer_unverified

    context 'when the Customer is verified' do
      let(:verified) { true }

      it 'reports nothing and does not read the row: the check does not apply' do
        run_check

        expect(issues).to be_empty
        expect(by_external_id).not_to have_received(:first)
      end
    end
  end

  # Not one of the four checks the #4744 review named, but it read the row
  # the same way and returned the same way.
  describe ':recovered_customer_unverified' do
    def run_check = doctor.send(:check_recovered_customer_unverified, issues)

    let(:verified)            { false }
    let(:provisioning_origin) { 'login_recovery' }

    include_examples 'a check that reports the unreadable row', :recovered_customer_unverified
  end

  describe 'one issue per customer' do
    it 'lists every check that could not run on a single issue, from one read' do
      doctor.send(:check_auth_email_drift, issues, repaired)
      doctor.send(:check_auth_email_canonical, issues)
      doctor.send(:check_auth_login_link, issues)

      expect(issues.size).to eq(1)
      expect(unreadable_issues.first[:checks_not_run])
        .to eq([:auth_email_drift, :auth_email_not_canonical, :auth_login_link])
      expect(unreadable_issues.first[:message])
        .to include('auth_email_drift, auth_email_not_canonical, auth_login_link')
      expect(by_external_id).to have_received(:first).once
    end

    it 'logs the read failure once, with the exception, and keeps the message out of the issue' do
      doctor.send(:check_auth_email_drift, issues, repaired)
      doctor.send(:check_auth_login_link, issues)

      expect(OT).to have_received(:le).with(/ur_c.*Sequel::DatabaseError.*column "login" does not exist/).once
      expect(unreadable_issues.first[:message]).not_to include('column "login"')
    end
  end

  describe 'states that stay silent' do
    def run_all
      doctor.send(:check_auth_email_drift, issues, repaired)
      doctor.send(:check_auth_email_canonical, issues)
      doctor.send(:check_auth_login_link, issues)
    end

    it 'reports nothing in simple mode (no auth database)' do
      allow(Auth::Database).to receive(:connection).and_return(nil)

      run_all

      expect(issues).to be_empty
    end

    it 'reports nothing when the customer has no accounts row' do
      allow(by_external_id).to receive(:first).and_return(nil)

      run_all

      expect(issues).to be_empty
    end
  end
end
