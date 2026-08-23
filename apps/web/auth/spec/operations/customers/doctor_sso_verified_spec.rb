# apps/web/auth/spec/operations/customers/doctor_sso_verified_spec.rb
#
# frozen_string_literal: true

# Unit tests for the :sso_customer_unverified check added to
# Auth::Operations::Customers::Doctor by #3973.
#
# The forward fix (config/hooks/omniauth.rb) stops NEW SSO signups drifting;
# this check is the only thing that heals the records created before it. Its
# whole value is in how narrow the gate is, so that is what these examples pin:
#
#   * Redis side — provisioning_origin must literally be 'sso_jit'. Any other
#     origin (or none) is left alone, because a bare "unverified customer with
#     a Verified account" describes ordinary password signups too.
#   * SQL side  — the accounts row must already be at AccountStatuses::VERIFIED.
#     The repair copies a fact the auth store holds; it never decides one.
#   * The repair writes REDIS ONLY (rodauth_already_synced: true) and PRESERVES
#     an existing verified_by rather than relabelling it 'sso'.
#
# Follows doctor_email_drift_spec.rb: the check is private and is exercised
# directly, so a failure names this check rather than dragging in the nine
# unrelated per-customer checks.
#
# Run: bundle exec rspec apps/web/auth/spec/operations/customers/doctor_sso_verified_spec.rb

require 'spec_helper'
require 'auth/database'
require 'auth/operations/customers/doctor'

RSpec.describe Auth::Operations::Customers::Doctor do
  let(:issues)   { [] }
  let(:repaired) { [] }

  let(:verified)            { false }
  let(:verified_by)         { nil }
  let(:provisioning_origin) { 'sso_jit' }
  let(:account_status)      { Auth::AccountStatuses::VERIFIED }
  let(:account_row)         { { id: 42, email: 'sso@example.com', status_id: account_status } }

  let(:customer) do
    double(
      'Customer',
      email: 'sso@example.com',
      objid: 'obj_c',
      extid: 'ur_c',
      obscure_email: 'ss***@e***.com',
      organization_instances: [],
      verified?: verified,
      verified_by: verified_by,
      provisioning_origin: provisioning_origin,
    )
  end

  let(:by_external_id) { double('by_external_id') }
  let(:accounts)       { double('accounts') }
  let(:db)             { double('db') }

  # Captures the SetCustomerVerification construction so the examples can assert
  # the contract arguments (verified_by preservation, rodauth_already_synced)
  # without touching Redis or SQL.
  let(:verification_calls) { [] }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:le)

    allow(Auth::Database).to receive(:connection).and_return(db)
    allow(db).to receive(:[]).with(:accounts).and_return(accounts)
    allow(accounts).to receive(:where).with(external_id: 'ur_c').and_return(by_external_id)
    allow(by_external_id).to receive(:select).with(:id, :email, :status_id).and_return(by_external_id)
    allow(by_external_id).to receive(:first).and_return(account_row)

    allow(Auth::Operations::SetCustomerVerification).to receive(:new) do |**kwargs|
      verification_calls << kwargs
      double('SetCustomerVerification', call: :success)
    end
  end

  def run(repair: false)
    described_class.new(customer: customer, repair: repair, actor: 'cli')
      .send(:check_sso_customer_unverified, issues, repaired)
  end

  describe 'detection' do
    it 'reports a high, repairable issue for an unverified sso_jit customer' do
      run

      expect(issues.size).to eq(1)
      expect(issues.first[:check]).to eq(:sso_customer_unverified)
      expect(issues.first[:severity]).to eq(:high)
      expect(issues.first[:repairable]).to be true
    end

    context 'when the customer is already verified' do
      let(:verified) { true }

      it 'reports nothing' do
        run
        expect(issues).to be_empty
      end
    end

    # The single most important negative: an ordinary password signup also has
    # an unverified Customer and (with verify_account disabled) a Verified
    # accounts row. Only real SSO provenance may be repaired.
    context 'when the customer was not provisioned via SSO' do
      let(:provisioning_origin) { 'canonical_signup' }

      it 'reports nothing' do
        run
        expect(issues).to be_empty
      end
    end

    context 'when provisioning_origin is absent' do
      let(:provisioning_origin) { nil }

      it 'reports nothing' do
        run
        expect(issues).to be_empty
      end
    end

    context 'when the Rodauth account is not Verified' do
      let(:account_status) { Auth::AccountStatuses::UNVERIFIED }

      it 'reports nothing — the auth store has not verified them either' do
        run
        expect(issues).to be_empty
      end
    end

    context 'when there is no Rodauth account row' do
      let(:account_row) { nil }

      it 'reports nothing' do
        run
        expect(issues).to be_empty
      end
    end
  end

  describe 'repair' do
    it 'routes the write through SetCustomerVerification without touching SQL' do
      run(repair: true)

      expect(verification_calls.size).to eq(1)
      expect(verification_calls.first).to include(
        customer: customer,
        verified: true,
        verified_by: 'sso',
        rodauth_already_synced: true,
      )
      expect(repaired).to eq([{ customer: 'ur_c', action: :sso_customer_verified, value: 'sso' }])
    end

    it 'does not write on a diagnostic (non-repair) run' do
      run

      expect(verification_calls).to be_empty
      expect(repaired).to be_empty
    end

    # Provenance is not ours to overwrite: a record that already says it was
    # email- or stripe-verified keeps saying so.
    context 'when the record already carries a verified_by' do
      let(:verified_by) { 'stripe_payment' }

      it 'preserves it instead of relabelling the record sso' do
        run(repair: true)

        expect(verification_calls.first[:verified_by]).to eq('stripe_payment')
        expect(repaired.first[:value]).to eq('stripe_payment')
        expect(issues.first[:repair_action]).to include('stripe_payment')
      end
    end

    it 'never aborts the sweep when the write raises' do
      allow(Auth::Operations::SetCustomerVerification).to receive(:new).and_raise(StandardError, 'boom')

      expect { run(repair: true) }.not_to raise_error
      expect(repaired).to be_empty
    end
  end

  describe 'registered provenance' do
    it "lists 'sso' as a valid verified_by value" do
      expect(described_class::VALID_VERIFIED_BY).to include('sso')
    end
  end
end
