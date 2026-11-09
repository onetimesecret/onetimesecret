# apps/web/auth/spec/operations/customers/doctor_login_link_spec.rb
#
# frozen_string_literal: true

# Unit tests for the ADR-051 checks added to Auth::Operations::Customers::Doctor:
#
#   :auth_login_missing            accounts row has no `login` yet (pre-backfill)
#   :auth_login_mismatch           `login` names a Customer other than the one
#                                  external_id names
#   :auth_email_verification_drift SQL email_verified_at disagrees with the
#                                  Customer's mailbox proof (mailbox_verified?,
#                                  Onetime::Customer::MAILBOX_VERIFIED_BY)
#   :email_index_blank_key         class-level sweep finds an empty-string key
#
# All report-only except the blank key, which --repair removes. The checks are
# exercised directly (not through #call) so a failure names the check.
#
# Run: tests/lanes/run unit --only apps/web/auth/spec/operations/customers/doctor_login_link_spec.rb

require 'spec_helper'
require 'auth/database'
require 'auth/operations/customers/doctor'

RSpec.describe Auth::Operations::Customers::Doctor do
  let(:issues)   { [] }
  let(:repaired) { [] }

  let(:customer) do
    double(
      'Customer',
      email: 'live@example.com',
      objid: 'obj_c',
      extid: 'ur_c',
      obscure_email: 'li***@e***.com',
      verified?: true,
      verified_by: 'email',
      mailbox_verified?: true,
      provisioning_origin: 'canonical_signup',
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:le)
  end

  def doctor(repair: false)
    described_class.new(customer: customer, repair: repair, actor: 'cli')
  end

  describe ':auth_login_*' do
    let(:by_external_id) { double('by_external_id') }
    let(:accounts)       { double('accounts') }
    let(:db)             { double('db') }

    def stub_row(row)
      allow(Auth::Database).to receive(:connection).and_return(db)
      allow(db).to receive(:[]).with(:accounts).and_return(accounts)
      allow(accounts).to receive(:where).with(external_id: 'ur_c').and_return(by_external_id)
      allow(by_external_id).to receive(:select).with(*described_class::AUTH_ACCOUNT_COLUMNS).and_return(by_external_id)
      allow(by_external_id).to receive(:first).and_return(row)
    end

    def base_row(**overrides)
      {
        id: 42,
        email: 'live@example.com',
        status_id: 2,
        login: 'obj_c',
        email_verified_at: Time.now,
        email_verified_by: 'email',
        email_verification_hold: nil,
      }.merge(overrides)
    end

    it 'reports nothing when login matches the Customer and verification agrees' do
      stub_row(base_row)

      doctor.send(:check_auth_login_link, issues)

      expect(issues).to be_empty
    end

    it 'reports :auth_login_missing (medium, manual) when login is NULL' do
      stub_row(base_row(login: nil))

      doctor.send(:check_auth_login_link, issues)

      expect(issues.map { |i| i[:check] }).to eq([:auth_login_missing])
      expect(issues.first).to include(severity: :medium, repairable: false)
      expect(issues.first[:repair_action]).to include('backfill-logins')
    end

    it 'reports :auth_login_mismatch (critical, manual) when login names another Customer' do
      stub_row(base_row(login: 'obj_other'))

      doctor.send(:check_auth_login_link, issues)

      expect(issues.map { |i| i[:check] }).to eq([:auth_login_mismatch])
      expect(issues.first).to include(severity: :critical, repairable: false)
    end

    it 'does not report verification drift on a mismatched row (one finding per row)' do
      stub_row(base_row(login: 'obj_other', email_verified_at: nil))

      doctor.send(:check_auth_login_link, issues)

      expect(issues.map { |i| i[:check] }).to eq([:auth_login_mismatch])
    end

    it 'reports :auth_email_verification_drift when SQL is unverified and the Customer is verified' do
      stub_row(base_row(email_verified_at: nil, email_verified_by: nil))

      doctor.send(:check_auth_login_link, issues)

      expect(issues.map { |i| i[:check] }).to eq([:auth_email_verification_drift])
      expect(issues.first).to include(severity: :high, repairable: false)
      expect(issues.first[:message]).to include('NULL')
    end

    it 'reports :auth_email_verification_drift when SQL is verified and the Customer is not' do
      allow(customer).to receive_messages(verified?: false, verified_by: '', mailbox_verified?: false)
      stub_row(base_row)

      doctor.send(:check_auth_login_link, issues)

      expect(issues.map { |i| i[:check] }).to eq([:auth_email_verification_drift])
      expect(issues.first).to include(auth_email_verified_by: 'email')
    end

    it "does not report drift for a Customer verified by an IdP claim ('sso' is not mailbox proof) and a NULL column" do
      allow(customer).to receive_messages(verified?: true, verified_by: 'sso', mailbox_verified?: false)
      stub_row(base_row(email_verified_at: nil, email_verified_by: nil))

      doctor.send(:check_auth_login_link, issues)

      expect(issues).to be_empty
    end

    it 'reports drift when the column is set but the Customer provenance is not mailbox proof' do
      allow(customer).to receive_messages(verified?: true, verified_by: 'sso', mailbox_verified?: false)
      stub_row(base_row(email_verified_by: 'sso'))

      doctor.send(:check_auth_login_link, issues)

      expect(issues.map { |i| i[:check] }).to eq([:auth_email_verification_drift])
      expect(issues.first[:message]).to include('mailbox_verified=false')
      expect(issues.first[:message]).to include('"sso"')
    end

    it 'skips the verification comparison when the row holds another address (auth_email_drift owns that)' do
      stub_row(base_row(email: 'other@example.com', email_verified_at: nil, email_verified_by: nil))

      doctor.send(:check_auth_login_link, issues)

      expect(issues).to be_empty
    end

    it 'compares the addresses case-insensitively' do
      stub_row(base_row(email: 'Live@Example.com', email_verified_at: nil, email_verified_by: nil))

      doctor.send(:check_auth_login_link, issues)

      expect(issues.map { |i| i[:check] }).to eq([:auth_email_verification_drift])
    end

    # The address test every verification writer uses (OT::Utils.same_mailbox?):
    # a decomposed accent is the same mailbox, so the row is judged.
    it 'judges a row whose address differs only by Unicode normalization' do
      allow(customer).to receive(:email).and_return("liv\u00E9@example.com")
      stub_row(base_row(email: "live\u0301@example.com", email_verified_at: nil, email_verified_by: nil))

      doctor.send(:check_auth_login_link, issues)

      expect(issues.map { |i| i[:check] }).to eq([:auth_email_verification_drift])
    end

    # And two addresses only case folding makes equal are not the same
    # mailbox, so the row is left to auth_email_drift.
    it 'skips a row whose address differs only by folding (ß and ss)' do
      allow(customer).to receive(:email).and_return('live@strasse.example')
      stub_row(base_row(email: 'live@straße.example', email_verified_at: nil, email_verified_by: nil))

      doctor.send(:check_auth_login_link, issues)

      expect(issues).to be_empty
    end

    it 'names the re-stamp procedure in the repair action' do
      stub_row(base_row(email_verified_at: nil, email_verified_by: nil))

      doctor.send(:check_auth_login_link, issues)

      expect(issues.first[:repair_action]).to include('unverify, then verify')
    end

    # Claude review on 9284e1c12: when the accounts row is the store with
    # the proof, re-stamping from the report gives the Customer the mailbox
    # proof has_system_role? requires (#4735), so the report never
    # prescribes it.
    it 'does not prescribe unverify, then verify when the accounts row has the proof' do
      allow(customer).to receive_messages(verified?: true, verified_by: 'sso', mailbox_verified?: false)
      stub_row(base_row)

      doctor.send(:check_auth_login_link, issues)

      expect(issues.map { |i| i[:check] }).to eq([:auth_email_verification_drift])
      expect(issues.first).to include(severity: :high, repairable: false)
      expect(issues.first[:repair_action]).not_to include('unverify')
      expect(issues.first[:repair_action]).to include('confirm the address')
    end

    # SyncSession#derive_verification_provenance never stamps mailbox proof
    # on a Customer recreated at login, so the row's proof outlives the
    # record it was written for. Expected, not a failed write.
    it 'reports a Customer recreated at login beside a row with proof as medium, with a manual decision' do
      allow(customer).to receive_messages(
        verified?: true, verified_by: 'legacy', mailbox_verified?: false, provisioning_origin: 'login_recovery',
      )
      stub_row(base_row)

      doctor.send(:check_auth_login_link, issues)

      expect(issues.map { |i| i[:check] }).to eq([:auth_email_verification_drift])
      expect(issues.first).to include(severity: :medium, repairable: false, auth_email_verified_by: 'email')
      expect(issues.first[:message]).to include('recreated at login')
      expect(issues.first[:repair_action]).to include('confirm the address')
      expect(issues.first[:repair_action]).not_to include('unverify')
    end

    it 'leaves an unverified Customer recreated at login to :recovered_customer_unverified' do
      allow(customer).to receive_messages(
        verified?: false, verified_by: '', mailbox_verified?: false, provisioning_origin: 'login_recovery',
      )
      stub_row(base_row)

      doctor.send(:check_auth_login_link, issues)

      expect(issues).to be_empty
    end

    it 'treats a held, unverified row as consistent with an unverified Customer' do
      allow(customer).to receive_messages(verified?: false, verified_by: '', mailbox_verified?: false)
      stub_row(base_row(email_verified_at: nil, email_verified_by: nil, email_verification_hold: 'idp_unverified'))

      doctor.send(:check_auth_login_link, issues)

      expect(issues).to be_empty
    end

    it 'does nothing when the row predates migration 015 (no :login key)' do
      stub_row({ id: 42, email: 'live@example.com', status_id: 2 })

      doctor.send(:check_auth_login_link, issues)

      expect(issues).to be_empty
    end

    it 'does nothing when there is no accounts row' do
      stub_row(nil)

      doctor.send(:check_auth_login_link, issues)

      expect(issues).to be_empty
    end

    # Reported rather than read as "no row" (doctor_auth_account_unreadable_spec.rb).
    it 'never aborts the sweep: a raising read is reported, not raised' do
      allow(Auth::Database).to receive(:connection).and_raise(StandardError, 'db down')

      expect { doctor.send(:check_auth_login_link, issues) }.not_to raise_error
      expect(issues.map { |issue| issue[:check] }).to eq([:auth_account_unreadable])
      expect(issues.first[:checks_not_run]).to eq([:auth_login_link])
    end
  end

  describe '.check_email_index with an empty-string key' do
    let(:email_index) { double('email_index') }

    before do
      allow(Onetime::Customer).to receive(:email_index).and_return(email_index)
      allow(email_index).to receive(:hgetall).and_return({ '' => 'obj_blank' })
      allow(email_index).to receive(:remove_field)
      allow(Onetime::Customer).to receive(:load).and_return(nil)
    end

    it 'reports :email_index_blank_key as critical and does not load a Customer for it' do
      result = described_class.check_email_index(repair: false)

      blank = result[:issues].find { |i| i[:check] == :email_index_blank_key }
      expect(blank).to include(severity: :critical, repairable: true, customer_objid: 'obj_blank')
      expect(result[:issues].map { |i| i[:check] }).not_to include(:email_index_stale)
      expect(Onetime::Customer).not_to have_received(:load)
      expect(email_index).not_to have_received(:remove_field)
    end

    it 'removes the key on repair and records the action' do
      result = described_class.check_email_index(repair: true)

      expect(email_index).to have_received(:remove_field).with('')
      expect(result[:repaired]).to include(hash_including(action: :email_index_blank_key_removed, customer_objid: 'obj_blank'))
    end
  end
end
