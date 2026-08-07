# apps/web/auth/spec/operations/sync_session_verification_reconcile_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::SyncSession#reconcile_verification_state
# (#3973).
#
# An SSO/OmniAuth-provisioned account is created already status=Verified by
# Rodauth (the IdP asserted the email), but Auth::Operations::CreateCustomer
# previously hardcoded verified: false unconditionally at creation time, with
# no path back to correct it: SyncSession only reconciled verification state
# on the branch where IT creates the customer record, never on the branch
# where it finds an already-existing one -- which is what happens on every
# subsequent SSO login, since the customer was already created by the
# OmniAuth callback on first login. This left an SSO-provisioned customer
# permanently unable to exercise any system role (has_system_role? gates on
# verified? before it checks the role field), even after promotion via
# `bin/ots customers role promote`.
#
# These examples drive #reconcile_verification_state directly (same pattern
# as sync_session_colonel_signin_spec.rb): the surrounding #call needs the
# auth database, and what needs pinning here is the reconcile decision itself.
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/sync_session_verification_reconcile_spec.rb

require 'spec_helper'
require 'auth/operations/sync_session'

RSpec.describe Auth::Operations::SyncSession do
  let(:session) { {} }
  let(:request) { double('Request', ip: '203.0.113.7', user_agent: 'rspec') }
  let(:db) { double('Sequel::Database') }

  def build_op(account)
    described_class.new(
      account: account,
      account_id: 42,
      session: session,
      request: request,
      correlation_id: 'corr_1',
      db: db,
    )
  end

  before do
    allow(Auth::Logging).to receive(:log_operation)
  end

  context 'when the Rodauth account is verified (status_id == 2) but the customer is not' do
    let(:op) { build_op({ email: 'sso-user@example.com', status_id: 2 }) }

    it 'sets the customer verified and stamps sso provenance' do
      customer = double('Customer', custid: 'sso-user@example.com', verified?: false)
      expect(customer).to receive(:verified=).with(true)
      expect(customer).to receive(:verified_by=).with('sso')
      expect(customer).to receive(:save_fields).with(:verified, :verified_by)

      op.send(:reconcile_verification_state, customer)
    end

    it 'logs the reconciliation' do
      customer = double('Customer', custid: 'sso-user@example.com', verified?: false)
      allow(customer).to receive(:verified=)
      allow(customer).to receive(:verified_by=)
      allow(customer).to receive(:save_fields)

      op.send(:reconcile_verification_state, customer)

      expect(Auth::Logging).to have_received(:log_operation).with(
        :customer_verification_reconciled,
        level: :info,
        customer_id: 'sso-user@example.com',
        correlation_id: 'corr_1',
      )
    end
  end

  context 'when the customer is already verified' do
    let(:op) { build_op({ email: 'user@example.com', status_id: 2 }) }

    it 'does not touch the record (no redundant writes on every login)' do
      customer = double('Customer', verified?: true)
      expect(customer).not_to receive(:verified=)
      expect(customer).not_to receive(:save_fields)

      op.send(:reconcile_verification_state, customer)
    end
  end

  context 'when the Rodauth account is not verified (status_id != 2)' do
    let(:op) { build_op({ email: 'unverified@example.com', status_id: 1 }) }

    it 'does not verify the customer (an unverified password signup stays unverified)' do
      customer = double('Customer', verified?: false)
      expect(customer).not_to receive(:verified=)
      expect(customer).not_to receive(:save_fields)

      op.send(:reconcile_verification_state, customer)
    end
  end
end
