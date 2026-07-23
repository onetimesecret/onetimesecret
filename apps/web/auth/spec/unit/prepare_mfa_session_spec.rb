# apps/web/auth/spec/unit/prepare_mfa_session_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::PrepareMfaSession
#
# Closes Gap 2 from issue #3854 (flagged in the 2026-07-19 security audit,
# "Two real test-coverage gaps on MFA enforcement").
#
# PrepareMfaSession#call is the writer for the awaiting_mfa session flag: when
# the login hook decides MFA is required, it sets session['awaiting_mfa'] = true
# (plus minimal account data) WITHOUT granting authenticated access. The
# SessionAuthStrategy then fails closed on that flag until the second factor
# completes (see session_auth_strategy_spec.rb, M-11).
#
# Before this spec nothing instantiated PrepareMfaSession — session_auth_strategy_spec
# only hard-coded 'awaiting_mfa' => true in a fake session hash. A regression in
# which key is written (string vs symbol), or an accidental 'authenticated' =>
# true leaking in here, would silently break the fail-closed contract. These
# tests call PrepareMfaSession.call against a real session hash and assert
# exactly which keys it sets.

require_relative '../spec_helper'
require_relative '../../operations/prepare_mfa_session'

RSpec.describe Auth::Operations::PrepareMfaSession do
  # A plain Hash stands in for the Rack session (the operation only uses []=).
  let(:session) { {} }

  describe '.call' do
    context 'with the minimal required inputs' do
      before do
        described_class.call(
          session: session,
          account_id: 123,
          email: 'user@example.com',
        )
      end

      it 'sets the awaiting_mfa flag under the STRING key' do
        expect(session['awaiting_mfa']).to be(true)
      end

      it 'stores account_id and email for the MFA UI' do
        expect(session['account_id']).to eq(123)
        expect(session['email']).to eq('user@example.com')
      end

      it 'does not set external_id or the correlation id when they are absent' do
        expect(session).not_to have_key('external_id')
        expect(session).not_to have_key(:mfa_correlation_id)
      end

      it 'never marks the session authenticated (fail-closed contract)' do
        expect(session).not_to have_key('authenticated')
        expect(session['authenticated']).to be_nil
      end
    end

    it 'returns true on success' do
      result = described_class.call(
        session: session,
        account_id: 123,
        email: 'user@example.com',
      )
      expect(result).to be(true)
    end

    context 'with an external_id and correlation_id' do
      before do
        described_class.call(
          session: session,
          account_id: 123,
          email: 'user@example.com',
          external_id: 'cust_abc123',
          correlation_id: 'auth_xyz789',
        )
      end

      it 'stores external_id under the STRING key' do
        expect(session['external_id']).to eq('cust_abc123')
      end

      it 'stores the correlation id under the SYMBOL key :mfa_correlation_id' do
        expect(session[:mfa_correlation_id]).to eq('auth_xyz789')
      end
    end

    context 'input coercion' do
      it 'coerces a String account_id to Integer' do
        described_class.call(session: session, account_id: '456', email: 'u@example.com')
        expect(session['account_id']).to eql(456)
      end

      it 'coerces a non-String external_id to String' do
        described_class.call(
          session: session,
          account_id: 1,
          email: 'u@example.com',
          external_id: 789,
        )
        expect(session['external_id']).to eq('789')
      end
    end

    context 'idempotency' do
      it 'is safe to call multiple times and leaves the flag set' do
        described_class.call(session: session, account_id: 1, email: 'u@example.com')

        expect {
          described_class.call(session: session, account_id: 1, email: 'u@example.com')
        }.not_to raise_error

        expect(session['awaiting_mfa']).to be(true)
        expect(session['account_id']).to eq(1)
      end
    end

    context 'when the session already holds unrelated data' do
      let(:session) { { 'shrimp' => 'csrf-token', 'return_to' => '/dashboard' } }

      it 'preserves the pre-existing keys' do
        described_class.call(session: session, account_id: 1, email: 'u@example.com')

        expect(session['shrimp']).to eq('csrf-token')
        expect(session['return_to']).to eq('/dashboard')
        expect(session['awaiting_mfa']).to be(true)
      end
    end
  end

  describe 'input validation' do
    it 'raises InvalidInput when the session is nil' do
      expect {
        described_class.call(session: nil, account_id: 1, email: 'u@example.com')
      }.to raise_error(described_class::InvalidInput, /session/)
    end

    it 'raises InvalidInput when account_id is nil' do
      expect {
        described_class.call(session: {}, account_id: nil, email: 'u@example.com')
      }.to raise_error(described_class::InvalidInput, /account_id/)
    end

    it 'raises InvalidInput when account_id is an empty string' do
      expect {
        described_class.call(session: {}, account_id: '', email: 'u@example.com')
      }.to raise_error(described_class::InvalidInput, /account_id/)
    end

    it 'raises InvalidInput when email is nil' do
      expect {
        described_class.call(session: {}, account_id: 1, email: nil)
      }.to raise_error(described_class::InvalidInput, /email/)
    end

    it 'raises InvalidInput when email is empty' do
      expect {
        described_class.call(session: {}, account_id: 1, email: '')
      }.to raise_error(described_class::InvalidInput, /email/)
    end

    it 'does not mutate the session when validation fails' do
      expect {
        described_class.call(session: session, account_id: nil, email: 'u@example.com')
      }.to raise_error(described_class::InvalidInput)

      expect(session).to be_empty
    end
  end
end
