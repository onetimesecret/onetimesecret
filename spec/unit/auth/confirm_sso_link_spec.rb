# spec/unit/auth/confirm_sso_link_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'sequel'
require 'auth/operations/confirm_sso_link'

# Unit tests for Auth::Operations::ConfirmSsoLink — the orchestration step of the
# #3840 Phase 4 mailbox-proof passwordless linking flow: load -> atomic single-use
# consume -> re-verify ownership + credential watermark -> (MFA gate) -> bind.
#
# Mirrors the real-DB approach of the Phase 4.0 bind_sso_identity spec: the accounts
# / account_identities / OTP tables are a REAL in-memory SQLite carrying the REAL
# (provider, issuer, uid) unique index, while the token is a REAL Familia record on
# the test database (port 2121) and the watermark reads a REAL Onetime::Customer.
# The end-to-end HTTP path (issue -> email -> confirm -> login) is Wave 2.
RSpec.describe Auth::Operations::ConfirmSsoLink do
  let(:db)         { build_auth_db }
  let(:identities) { db[:account_identities] }

  let(:account_id) { 42 }
  let(:email)      { 'user@example.com' }
  let(:provider)   { 'google' }
  let(:issuer)     { 'https://accounts.google.com' }
  let(:uid)        { 'sub-123' }
  let(:sid)        { 'a' * 64 }

  let(:tokens)    { [] }
  let(:customers) { [] }

  # Minimal real SQLite mirroring the columns the op + BindSsoIdentity + MfaStateChecker
  # touch. Kept local (not RodauthTestHelper) so this stays in the top-level unit lane
  # where Familia is connected to Valkey.
  def build_auth_db
    db = Sequel.sqlite
    db.create_table(:accounts) do
      primary_key :id, type: :Bignum
      String :email, null: false
      String :external_id
      Integer :status_id, null: false, default: 2
    end
    db.create_table(:account_identities) do
      primary_key :id, type: :Bignum
      foreign_key :account_id, :accounts, type: :Bignum, null: false
      String :provider, null: false
      String :issuer, null: false, default: ''
      String :uid, null: false
      index %i[provider issuer uid], unique: true
    end
    db.create_table(:account_otp_keys) do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      String :key, null: false
      Integer :num_failures, null: false, default: 0
      Time :last_use, null: false, default: Sequel::CURRENT_TIMESTAMP
    end
    db.create_table(:account_recovery_codes) do
      foreign_key :id, :accounts, type: :Bignum
      String :code
      primary_key %i[id code]
    end
    db
  end

  def seed_account(id: account_id, account_email: email, external_id: nil, status_id: 2)
    db[:accounts].insert(id: id, email: account_email, external_id: external_id, status_id: status_id)
    id
  end

  def issue_token(**overrides)
    record = Onetime::SsoLinkVerification.issue(
      provider: provider,
      uid: uid,
      email: overrides.fetch(:email, email),
      account_id: overrides.fetch(:account_id, account_id),
      sid: overrides.fetch(:sid, sid),
      password_watermark: overrides.fetch(:password_watermark, 0),
      issuer: issuer,
    )
    tokens << record
    record.token
  end

  def confirm(token, current_sid: sid, mfa_feature_loaded: false)
    described_class.call(
      db: db, token: token, current_sid: current_sid, mfa_feature_loaded: mfa_feature_loaded,
    )
  end

  # Unique email per example so Customer's unique email-index (which delete! does
  # not fully clear on the test DB) never collides across runs.
  def unique_email(prefix)
    "#{prefix}-#{SecureRandom.hex(4)}@example.com"
  end

  def customer_with_watermark(customer_email, watermark)
    customer = Onetime::Customer.create!(customer_email)
    customers << customer
    customer.last_password_update! watermark
    customer
  end

  # Capture every audit event name emitted during the block's op call.
  def with_captured_events
    events = []
    allow(Auth::Logging).to receive(:log_auth_event).and_wrap_original do |orig, event, **kw|
      events << event
      orig.call(event, **kw)
    end
    events
  end

  after do
    tokens.each { |t| Onetime::SsoLinkVerification.load(t)&.delete! rescue nil }
    customers.each { |c| c.delete! rescue nil }
  end

  describe 'fresh confirmation (happy path)' do
    it 'binds the identity, returns :ok bound with account context, and audits the consume' do
      seed_account
      events = with_captured_events
      token  = issue_token

      result = confirm(token)

      expect(result).to have_attributes(
        status: :ok, bound: true, second_factor_pending: false,
        account_id: account_id.to_s, email: email, provider: provider,
      )
      expect(result.ok?).to be(true)

      rows = identities.where(provider: provider, issuer: issuer, uid: uid).all
      expect(rows.size).to eq(1)
      expect(rows.first[:account_id]).to eq(account_id)

      expect(events).to include(:sso_link_verification_confirmed)
    end
  end

  describe 'single-use consume' do
    it 'succeeds once then reports :link_expired on a second confirmation of the same token' do
      seed_account
      token = issue_token

      expect(confirm(token).status).to eq(:ok)
      expect(confirm(token).status).to eq(:link_expired)

      # The winning bind is the only row — the second call bound nothing.
      expect(identities.where(provider: provider, issuer: issuer, uid: uid).count).to eq(1)
    end
  end

  describe 'missing / vanished' do
    it 'returns :link_expired for an unknown token' do
      seed_account
      expect(confirm('does-not-exist').status).to eq(:link_expired)
    end

    it 'returns :link_expired when the snapshotted account no longer exists' do
      token = issue_token # no account seeded
      expect(confirm(token).status).to eq(:link_expired)
    end
  end

  describe 'soft, cross-device session binding' do
    it 'confirms with NO cross-device warning when the current sid matches the initiating sid' do
      seed_account
      events = with_captured_events
      token  = issue_token(sid: sid)

      expect(confirm(token, current_sid: sid).status).to eq(:ok)
      expect(events).not_to include(:sso_link_verification_cross_device)
    end

    it 'still confirms (soft path) but warns when the current sid differs from the initiating sid' do
      seed_account
      events = with_captured_events
      token  = issue_token(sid: sid)

      result = confirm(token, current_sid: 'f' * 64)
      expect(result.status).to eq(:ok)
      expect(result.bound).to be(true)
      expect(events).to include(:sso_link_verification_cross_device)
    end
  end

  describe 'conflict handling' do
    it 'returns :link_conflict without binding when the identity is owned by a DIFFERENT account' do
      seed_account
      other = seed_account(id: 999, account_email: 'other@example.com')
      identities.insert(provider: provider, issuer: issuer, uid: uid, account_id: other)

      expect(confirm(issue_token).status).to eq(:link_conflict)

      # The existing row still belongs to the other account — nothing rebound.
      row = identities.where(provider: provider, issuer: issuer, uid: uid).first
      expect(row[:account_id]).to eq(other)
    end

    it 'returns :link_conflict when the account was re-emailed since issuance (no bind)' do
      seed_account(account_email: 'changed@example.com')
      token = issue_token(email: email) # token still carries the OLD email

      expect(confirm(token).status).to eq(:link_conflict)
      expect(identities.where(provider: provider, issuer: issuer, uid: uid).count).to eq(0)
    end
  end

  describe 'credential-change invalidation (watermark)' do
    it 'returns :link_invalidated when the account watermark advanced after issuance' do
      wm_email = unique_email('wm-adv')
      customer = customer_with_watermark(wm_email, 200)

      seed_account(account_email: wm_email, external_id: customer.extid)
      token = issue_token(email: wm_email, password_watermark: 100)

      expect(confirm(token).status).to eq(:link_invalidated)
      expect(identities.where(provider: provider, issuer: issuer, uid: uid).count).to eq(0)
    end

    it 'confirms when the watermark is unchanged since issuance' do
      wm_email = unique_email('wm-eq')
      customer = customer_with_watermark(wm_email, 150)

      seed_account(account_email: wm_email, external_id: customer.extid)
      token = issue_token(email: wm_email, password_watermark: 150)

      expect(confirm(token).status).to eq(:ok)
    end
  end

  describe 'MFA-safe bind' do
    it 'DEFERS the bind (bound: false) when a second factor is pending' do
      seed_account
      db[:account_otp_keys].insert(id: account_id, key: 'otpsecret', num_failures: 0)
      events = with_captured_events
      token  = issue_token

      result = confirm(token, mfa_feature_loaded: true)

      expect(result).to have_attributes(status: :ok, bound: false, second_factor_pending: true)
      # No identity bound this round — the deferred-MFA follow-up completes it.
      expect(identities.where(provider: provider, issuer: issuer, uid: uid).count).to eq(0)
      expect(events).to include(:sso_link_verification_deferred_mfa)
    end

    it 'binds normally when the OTP feature is not loaded even if an OTP row exists' do
      seed_account
      db[:account_otp_keys].insert(id: account_id, key: 'otpsecret', num_failures: 0)

      result = confirm(issue_token, mfa_feature_loaded: false)
      expect(result).to have_attributes(status: :ok, bound: true)
      expect(identities.where(provider: provider, issuer: issuer, uid: uid).count).to eq(1)
    end
  end
end
