# spec/unit/auth/password_modification_gate_spec.rb
#
# frozen_string_literal: true

# Cohort coverage for the shared challengeable-password probe backing BOTH:
#   - the SSO-linking interstitial minting decision (hooks/omniauth.rb), and
#   - the password-modification gate (features/mfa.rb:
#     modifications_require_password? / two_factor_modifications_require_password?).
#
# Security context (review finding, 2026-08-11): Rodauth's bare has_password?
# reads only account_password_hashes, so the pre-migration cohort whose
# password still lives in Redis (overrides/password_migration.rb verifies it in
# password_match?) looked password-LESS to a has_password?-only gate — a
# hijacked session could change/strip credentials with zero re-auth. The gate
# must hold three cohorts apart:
#   1. argon2 hash in account_password_hashes  -> password REQUIRED
#   2. Redis-only legacy passphrase            -> password REQUIRED
#   3. no password anywhere (SSO-only)         -> EXEMPT
#
# Lives in spec/unit/ (top-level lane): the Redis probe reads a real
# Onetime::Customer, and only this harness connects Familia for unit specs.

require 'spec_helper'
require 'sequel'
require 'securerandom'
require 'rodauth'

# The hooks file uses the compact `module Auth::Config::Hooks` form, so the
# namespace chain must exist before the require. Guarded: if the real app was
# already loaded in this process, reuse its constants.
module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Hooks, Module.new) unless Auth::Config.const_defined?(:Hooks, false)

require 'auth/lib/logging'
require 'auth/config/hooks/omniauth'

# Named for the concept (the password-modification gate), not the module path:
# the probe is shared plumbing; the gate is what the cohorts exercise.
# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe Auth::Config::Hooks::OmniAuth, '.account_has_challengeable_password?' do
  subject(:probe) { described_class }

  let(:db) do
    db = Sequel.sqlite
    db.create_table(:accounts) do
      primary_key :id, type: :Bignum
      String :email, null: false
    end
    db.create_table(:account_password_hashes) do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      String :password_hash, null: false
    end
    db
  end

  # Unique email per example: Customer.create! leaks its unique email index on
  # the test datastore, so a fixed literal collides across runs.
  let(:email) { "gate-#{SecureRandom.hex(4)}@example.com" }

  let(:account_id) { db[:accounts].insert(email: email) }
  let(:hash_ds)    { db[:account_password_hashes].where(id: account_id) }

  def call(error_result: false)
    probe.account_has_challengeable_password?(
      hash_ds, email, 'password_modification_gate', error_result: error_result
    )
  end

  context 'with an argon2 hash in account_password_hashes (cohort 1)' do
    before { db[:account_password_hashes].insert(id: account_id, password_hash: 'argon2-hash') }

    it 'is challengeable (password required)' do
      expect(call).to be true
    end

    it 'never reaches the Redis probe' do
      allow(Onetime::Customer).to receive(:email_exists?)
      call
      expect(Onetime::Customer).not_to have_received(:email_exists?)
    end
  end

  context 'with a Redis-only legacy passphrase (cohort 2, pre-migration)' do
    before do
      customer = Onetime::Customer.create!(email: email)
      customer.update_passphrase!('legacy-secret')
    end

    it 'starts from an empty SQL side (precondition)' do
      expect(hash_ds.any?).to be false
    end

    it 'is challengeable — has_password? alone cannot see this' do
      expect(call).to be true
    end
  end

  context 'without a password anywhere (cohort 3, SSO-only account)' do
    it 'is exempt when the Customer exists but has no passphrase' do
      Onetime::Customer.create!(email: email)
      expect(call).to be false
    end

    it 'is exempt when no Customer record exists at all' do
      expect(call).to be false
    end
  end

  context "when the probe itself errors (fail direction is the caller's choice)" do
    before do
      allow(Onetime::Customer).to receive(:email_exists?)
        .and_raise(StandardError, 'redis down')
    end

    it 'defaults to false — the omniauth interstitial falls through to refusal' do
      expect(call).to be false
    end

    it 'returns true with error_result: true — the modification gate fails CLOSED' do
      expect(call(error_result: true)).to be true
    end

    it 'still short-circuits true on the SQL hash without reaching the broken probe' do
      db[:account_password_hashes].insert(id: account_id, password_hash: 'argon2-hash')
      expect(call(error_result: false)).to be true
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
