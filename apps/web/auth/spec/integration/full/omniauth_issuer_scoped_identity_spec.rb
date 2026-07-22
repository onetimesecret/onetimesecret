# apps/web/auth/spec/integration/full/omniauth_issuer_scoped_identity_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# Issue: #3840 Phase 0 / #3838 item 5 — cross-tenant SSO account takeover.
#
# Drives the SHIPPED issuer-scoped identity lookup
# (Auth::Config::Features::OmniAuth.lookup_identity) against the REAL migrated
# account_identities schema (migration 008 runs during boot). This exercises
# the persistence + decision layer end-to-end:
#   (a) takeover regression — two tenants, provider='oidc', colliding uid,
#       different issuer → two rows, tenant B resolves to tenant B's account,
#       never tenant A's (no cross-bind); a true (provider, issuer, uid)
#       duplicate is rejected by the unique index.
#   (b) platform grace + lazy upgrade — a legacy (provider, '', uid) row + a
#       PLATFORM callback resolving a real issuer matches the legacy row AND
#       upgrades its issuer column.
#   (c) tenant no-grace — the same legacy row + a TENANT callback (validated
#       domain present) does NOT match the legacy row and leaves it untouched.
#
# SCOPE NOTE: this does NOT drive the full HTTP OmniAuth callback (that needs a
# mocked IdP strategy + request cycle). It drives the exact production function
# the retrieve_omniauth_identity override delegates to, against a real DB.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTHENTICATION_MODE=full, AUTH_DATABASE_URL=sqlite::memory: (rake sets this)
#
# RUN:
#   bundle exec rake spec:integration:full
# =============================================================================

require_relative '../../spec_helper'

RSpec.describe 'Issuer-scoped SSO identity lookup', type: :integration do
  before(:all) do
    require 'onetime' unless defined?(Onetime)
    Onetime.boot! :test unless Onetime.ready?
  end

  let(:feature) { Auth::Config::Features::OmniAuth }
  let(:db) { Auth::Database.connection }
  let(:ds) { db[:account_identities] }
  let(:cols) { { id_col: :id, provider_col: :provider, uid_col: :uid, issuer_col: :issuer } }

  # Track inserted rows for cleanup (shared in-memory DB across specs).
  let(:created_account_ids) { [] }
  let(:created_identity_ids) { [] }

  after do
    # Identities first, then accounts (FK order). Deletes are idempotent, so a
    # partially-populated list is safe. A cleanup error is a real problem and is
    # allowed to surface rather than leave stray rows in the shared in-memory DB
    # that would make later examples order-dependent.
    created_identity_ids.each { |id| ds.where(id: id).delete }
    created_account_ids.each { |id| db[:accounts].where(id: id).delete }
  end

  def create_account(email)
    id = db[:accounts].insert(email: email, status_id: 1)
    created_account_ids << id
    id
  end

  def insert_identity(account_id:, provider:, issuer:, uid:)
    id = ds.insert(account_id: account_id, provider: provider, issuer: issuer, uid: uid)
    created_identity_ids << id
    id
  end

  def unique_email(prefix)
    "#{prefix}-#{SecureRandom.hex(6)}@issuer-scoped-test.example.com"
  end

  describe 'schema' do
    it 'has a NOT NULL issuer column keyed with (provider, issuer, uid)' do
      schema = db.schema(:account_identities).to_h { |c, info| [c, info] }
      expect(schema).to have_key(:issuer)
      expect(schema[:issuer][:allow_null]).to be false

      composite = db.indexes(:account_identities).values.find { |i| i[:columns] == %i[provider issuer uid] }
      expect(composite).not_to be_nil
      expect(composite[:unique]).to be true
    end
  end

  describe '(a) takeover regression: colliding uid, different issuer' do
    let(:uid) { "sub-#{SecureRandom.hex(6)}" }
    let!(:acct_a) { create_account(unique_email('tenant-a')) }
    let!(:acct_b) { create_account(unique_email('tenant-b')) }

    before do
      insert_identity(account_id: acct_a, provider: 'oidc', issuer: 'https://idp-a.example', uid: uid)
      insert_identity(account_id: acct_b, provider: 'oidc', issuer: 'https://idp-b.example', uid: uid)
    end

    it 'stores two distinct rows for the same (provider, uid)' do
      expect(ds.where(provider: 'oidc', uid: uid).count).to eq(2)
    end

    it 'rejects a true (provider, issuer, uid) duplicate' do
      expect do
        ds.insert(account_id: acct_b, provider: 'oidc', issuer: 'https://idp-a.example', uid: uid)
      end.to raise_error(Sequel::UniqueConstraintViolation)
    end

    it 'binds tenant B to tenant B account, never tenant A (no cross-bind)' do
      row_b = feature.lookup_identity(ds: ds, **cols, provider: 'oidc', uid: uid,
                                                      resolved_issuer: 'https://idp-b.example',
                                                      platform_path: false)
      expect(row_b[:account_id]).to eq(acct_b)
      expect(row_b[:account_id]).not_to eq(acct_a)
    end

    it 'binds tenant A to tenant A account' do
      row_a = feature.lookup_identity(ds: ds, **cols, provider: 'oidc', uid: uid,
                                                      resolved_issuer: 'https://idp-a.example',
                                                      platform_path: false)
      expect(row_a[:account_id]).to eq(acct_a)
    end
  end

  describe '(b) platform grace + lazy upgrade' do
    let(:uid) { "legacy-#{SecureRandom.hex(6)}" }
    let!(:acct) { create_account(unique_email('platform-legacy')) }
    let!(:identity_id) { insert_identity(account_id: acct, provider: 'oidc', issuer: '', uid: uid) }

    it 'matches the legacy "" row and upgrades its issuer in the DB' do
      row = feature.lookup_identity(ds: ds, **cols, provider: 'oidc', uid: uid,
                                                    resolved_issuer: 'https://real-idp.example',
                                                    platform_path: true)
      expect(row[:account_id]).to eq(acct)
      expect(row[:issuer]).to eq('https://real-idp.example')
      expect(ds.where(id: identity_id).get(:issuer)).to eq('https://real-idp.example')
    end
  end

  describe '(c) tenant no-grace' do
    let(:uid) { "legacy-#{SecureRandom.hex(6)}" }
    let!(:acct) { create_account(unique_email('tenant-legacy')) }
    let!(:identity_id) { insert_identity(account_id: acct, provider: 'oidc', issuer: '', uid: uid) }

    it 'does NOT match the legacy "" row and leaves it untouched' do
      row = feature.lookup_identity(ds: ds, **cols, provider: 'oidc', uid: uid,
                                                    resolved_issuer: 'https://tenant-idp.example',
                                                    platform_path: false)
      expect(row).to be_nil
      expect(ds.where(id: identity_id).get(:issuer)).to eq('')
    end
  end
end
