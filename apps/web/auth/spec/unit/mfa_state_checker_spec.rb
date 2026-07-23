# apps/web/auth/spec/unit/mfa_state_checker_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::MfaStateChecker
#
# Closes Gap 1 from issue #3854 (flagged in the 2026-07-19 security audit,
# "Two real test-coverage gaps on MFA enforcement").
#
# MfaStateChecker#check is the DB-backed half of MFA enforcement: it reads
# account_otp_keys and counts account_recovery_codes to derive the
# has_otp_secret / has_recovery_codes booleans that DetectMfaRequirement then
# turns into a requires-MFA decision (see apps/web/auth/config/hooks/login.rb).
#
# detect_mfa_requirement_spec.rb already covers the pure decision logic, but it
# passes those booleans as hard-coded values — the real table/count logic in
# #query_mfa_state never ran under test. A silent regression there (wrong table,
# wrong id column, a JOIN that drops rows) would weaken MFA enforcement with
# nothing to catch it. These tests seed real rows in an in-memory SQLite DB and
# assert the state object #check returns.

require_relative '../spec_helper'
require_relative '../../operations/mfa_state_checker'

RSpec.describe Auth::Operations::MfaStateChecker do
  # In-memory SQLite with the full Rodauth schema (account_otp_keys,
  # account_recovery_codes, accounts, ...). See RodauthTestHelper.
  let(:db) { create_test_database }

  # A logger that swallows every structured call. Injecting it keeps the test
  # hermetic (no dependency on Onetime.get_logger / global boot state) and
  # quiet, while still exercising the real DB query path.
  let(:null_logger) do
    Object.new.tap do |logger|
      def logger.method_missing(_name, *_args, **_kwargs); nil; end
      def logger.respond_to_missing?(_name, _include_private = false); true; end
    end
  end

  subject(:checker) { described_class.new(db, logger: null_logger) }

  # --- seed helpers --------------------------------------------------------

  # Insert a real account row; status_id defaults, email must be unique.
  # @return [Integer] the generated account_id
  def create_account(email)
    db[:accounts].insert(email: email)
  end

  # account_otp_keys.id IS the account_id (FK + PK). `key` is NOT NULL.
  def add_otp_key(account_id, last_use: Time.now)
    db[:account_otp_keys].insert(
      id: account_id,
      key: SecureRandom.hex(20),
      last_use: last_use,
    )
  end

  # account_recovery_codes has composite PK [id, code]; id is the account_id.
  # Codes are deleted when used, so row count == unused-code count.
  def add_recovery_codes(account_id, count)
    count.times do |i|
      db[:account_recovery_codes].insert(id: account_id, code: "code-#{account_id}-#{i}")
    end
  end

  describe '#check' do
    context 'when the account has neither OTP nor recovery codes' do
      let(:account_id) { create_account('none@example.com') }

      it 'reports no MFA configured' do
        state = checker.check(account_id)

        expect(state.account_id).to eq(account_id)
        expect(state.has_otp_secret).to be(false)
        expect(state.has_recovery_codes).to be(false)
        expect(state.unused_recovery_code_count).to eq(0)
        expect(state.otp_last_use).to be_nil
        expect(state.mfa_enabled?).to be(false)
        expect(state.available_methods).to eq([])
        expect(state.reason).to eq('no_mfa_configured')
      end
    end

    context 'when the account has an OTP secret only' do
      let(:account_id) { create_account('otp@example.com') }

      before { add_otp_key(account_id) }

      it 'reads has_otp_secret=true from account_otp_keys' do
        state = checker.check(account_id)

        expect(state.has_otp_secret).to be(true)
        expect(state.has_recovery_codes).to be(false)
        expect(state.unused_recovery_code_count).to eq(0)
        expect(state.otp_last_use).not_to be_nil
        expect(state.mfa_enabled?).to be(true)
        expect(state.available_methods).to eq([:otp])
        expect(state.reason).to eq('otp_configured')
      end
    end

    context 'when the account has recovery codes only' do
      let(:account_id) { create_account('recovery@example.com') }

      before { add_recovery_codes(account_id, 3) }

      it 'reads has_recovery_codes=true and the exact unused count' do
        state = checker.check(account_id)

        expect(state.has_otp_secret).to be(false)
        expect(state.has_recovery_codes).to be(true)
        expect(state.unused_recovery_code_count).to eq(3)
        expect(state.otp_last_use).to be_nil
        expect(state.mfa_enabled?).to be(true)
        expect(state.available_methods).to eq([:recovery_codes])
        expect(state.reason).to eq('recovery_codes_only')
      end
    end

    context 'when the account has both OTP and recovery codes' do
      let(:account_id) { create_account('both@example.com') }

      before do
        add_otp_key(account_id)
        add_recovery_codes(account_id, 5)
      end

      it 'reports both methods and the recovery-code count' do
        state = checker.check(account_id)

        expect(state.has_otp_secret).to be(true)
        expect(state.has_recovery_codes).to be(true)
        expect(state.unused_recovery_code_count).to eq(5)
        expect(state.mfa_enabled?).to be(true)
        expect(state.available_methods).to eq([:otp, :recovery_codes])
        expect(state.reason).to eq('otp_and_recovery_configured')
      end
    end

    context 'when account_id is passed as a String' do
      let(:account_id) { create_account('string-id@example.com') }

      before { add_otp_key(account_id) }

      it 'coerces to Integer and still reads the right row' do
        state = checker.check(account_id.to_s)

        expect(state.account_id).to eq(account_id)
        expect(state.account_id).to be_a(Integer)
        expect(state.has_otp_secret).to be(true)
      end
    end

    context 'when the account_id does not exist' do
      it 'returns an all-false state rather than raising' do
        state = checker.check(999_999)

        expect(state.has_otp_secret).to be(false)
        expect(state.has_recovery_codes).to be(false)
        expect(state.unused_recovery_code_count).to eq(0)
        expect(state.otp_last_use).to be_nil
        expect(state.mfa_enabled?).to be(false)
      end
    end

    context 'data isolation between accounts' do
      it 'counts only the rows belonging to the queried account' do
        account_a = create_account('a@example.com')
        account_b = create_account('b@example.com')

        add_otp_key(account_a)
        add_recovery_codes(account_a, 2)
        # account_b intentionally left with no MFA rows.

        state_b = checker.check(account_b)
        expect(state_b.has_otp_secret).to be(false)
        expect(state_b.has_recovery_codes).to be(false)
        expect(state_b.unused_recovery_code_count).to eq(0)

        state_a = checker.check(account_a)
        expect(state_a.has_otp_secret).to be(true)
        expect(state_a.unused_recovery_code_count).to eq(2)
      end
    end
  end

  # The caching path is part of #check's public contract: when cache_ttl is set,
  # a State is served from an in-process cache until clear_cache invalidates it.
  # Covering it guards the "did we accidentally re-query / never cache" regressions.
  describe 'caching (cache_ttl set)' do
    subject(:checker) { described_class.new(db, logger: null_logger, cache_ttl: 60) }

    it 'serves the cached State on a subsequent check within the TTL' do
      account_id = create_account('cache@example.com')

      first = checker.check(account_id)
      expect(first.has_otp_secret).to be(false)

      # Mutate the DB *after* the first read was cached.
      add_otp_key(account_id)

      second = checker.check(account_id)
      expect(second).to equal(first), 'expected the cached State object to be returned'
      expect(second.has_otp_secret).to be(false)
    end

    it 're-reads the DB after clear_cache' do
      account_id = create_account('cache-clear@example.com')

      checker.check(account_id)
      add_otp_key(account_id)
      checker.clear_cache(account_id)

      refreshed = checker.check(account_id)
      expect(refreshed.has_otp_secret).to be(true)
    end
  end
end
