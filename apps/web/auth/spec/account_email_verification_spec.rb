# apps/web/auth/spec/account_email_verification_spec.rb
#
# frozen_string_literal: true

# The one mapping from a Customer's verification state to the migration 015
# columns (ADR-051). The backfill, SetCustomerVerification, the
# after_verify_account and invite-signup hooks, ChangeEmail and the doctor all
# derive the columns here; the integration specs pin each writer.

require 'spec_helper'
require 'auth/account_email_verification'

RSpec.describe Auth::AccountEmailVerification do
  describe '.values' do
    it 'records proof for every mailbox-proof provenance' do
      Onetime::Customer::MAILBOX_VERIFIED_BY.each do |tag|
        expect(described_class.values(verified: true, verified_by: tag)).to eq(
          email_verified_at: Sequel::CURRENT_TIMESTAMP,
          email_verified_by: tag,
          email_verification_hold: nil,
        )
      end
    end

    it 'records no proof for a provenance that is not mailbox proof' do
      (Onetime::Customer::VERIFIED_BY_VALUES - Onetime::Customer::MAILBOX_VERIFIED_BY).each do |tag|
        expect(described_class.values(verified: true, verified_by: tag)).to eq(described_class::CLEARED)
      end
    end

    it 'records no proof for an unverified Customer whatever its stale tag says' do
      expect(described_class.values(verified: false, verified_by: 'email')).to eq(described_class::CLEARED)
    end

    it 'copies a hold, never beside proof' do
      expect(described_class.values(verified: true, verified_by: 'sso', hold: 'idp_unverified'))
        .to eq(described_class::CLEARED.merge(email_verification_hold: 'idp_unverified'))
      expect(described_class.values(verified: true, verified_by: 'email', hold: 'idp_unverified'))
        .to include(email_verified_by: 'email', email_verification_hold: nil)
    end
  end

  describe '.values_for_row' do
    it 'maps the state for a row at the Customer address, case aside' do
      expect(described_class.values_for_row('User@Example.com', 'user@example.com', verified: true, verified_by: 'email'))
        .to include(email_verified_by: 'email')
    end

    it 'clears the columns for a row at another mailbox, folding included' do
      expect(described_class.values_for_row('a@example.com', 'b@example.com', verified: true, verified_by: 'email'))
        .to eq(described_class::CLEARED)
      expect(described_class.values_for_row('u@straße.example', 'u@strasse.example', verified: true, verified_by: 'email'))
        .to eq(described_class::CLEARED)
    end
  end

  describe '.in_step?' do
    let(:proof) { { email_verified_at: Time.utc(2026, 11, 8), email_verified_by: 'email', email_verification_hold: nil } }

    it 'ignores the proof time, so a repeat never moves it' do
      expect(described_class.in_step?(proof, described_class.values(verified: true, verified_by: 'email'))).to be(true)
    end

    it 'tells a different provenance or missing proof apart' do
      expect(described_class.in_step?(proof, described_class.values(verified: true, verified_by: 'cli_provision')))
        .to be(false)
      expect(described_class.in_step?(proof, described_class::CLEARED)).to be(false)
    end
  end

  describe '.columns?' do
    it 'reads the accounts schema and treats a schema error as no columns' do
      with_columns = double('db', schema: [[:id, {}], [:email_verified_at, {}]])
      without      = double('db', schema: [[:id, {}]])
      broken       = double('db')
      allow(broken).to receive(:schema).and_raise(Sequel::Error, 'no such table')

      expect(described_class.columns?(with_columns)).to be(true)
      expect(described_class.columns?(without)).to be(false)
      expect(described_class.columns?(broken)).to be(false)
    end
  end
end
