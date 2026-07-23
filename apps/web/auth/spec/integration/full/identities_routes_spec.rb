# apps/web/auth/spec/integration/full/identities_routes_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# Issue: #3840 Phase 2 — JSON API to manage an account's linked SSO identities
#        (apps/web/auth/routes/identities.rb).
#
# WHAT IT LOCKS IN:
#   - GET  /auth/identities lists ONLY the current account's rows (no leak).
#   - DELETE /auth/identities/:id removes a row iff it belongs to the caller;
#     a cross-account id yields 404 and deletes nothing (no IDOR).
#   - Unauthenticated requests are rejected (401).
#   - Last-credential safety: an SSO-only account (no usable password) may not
#     delete its final identity (409); an account WITH a password may.
#   - `uid` is masked in the list response.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTHENTICATION_MODE=full, AUTH_DATABASE_URL (SQLite in-memory)
#
# RUN:
#   RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL=sqlite::memory: \
#     ORGS_SSO_ENABLED=true LANG=en_US.UTF-8 \
#     bundle exec rspec apps/web/auth/spec/integration/full/identities_routes_spec.rb \
#     --tag '~postgres_database'
# =============================================================================

require_relative '../../spec_helper'

RSpec.describe 'Linked identities management API (#3840 Phase 2)', type: :integration do
  include Rack::Test::Methods

  # Password is AuthTestConstants::TEST_PASSWORD (shared across spec files so a
  # top-level constant isn't redefined when both specs load in one process).

  def app
    Onetime::Application::Registry.generate_rack_url_map
  end

  before(:all) do
    require 'onetime'
    require 'onetime/application/registry'
    require 'onetime/auth_config'

    Onetime.auth_config.reload! if Onetime.respond_to?(:auth_config) && Onetime.auth_config.respond_to?(:reload!)
    Onetime::Application::Registry.reset! if Onetime::Application::Registry.respond_to?(:reset!)

    Onetime.boot!(:test, force: true)

    Onetime::Application::Registry.prepare_application_registry

    mounts = Onetime::Application::Registry.mount_mappings.keys
    raise "Auth app not mounted post-boot: #{mounts.inspect}" unless mounts.any? { |m| m.include?('/auth') }
  end

  let(:identities) { auth_db[:account_identities] }

  # ==========================================================================
  # Helpers
  # ==========================================================================

  def seed_account_with_password(email, password: AuthTestConstants::TEST_PASSWORD)
    normalized = OT::Utils.normalize_email(email)
    customer   = Onetime::Customer.new(email: normalized)
    customer.save
    account_id = auth_db[:accounts].insert(
      email: normalized,
      status_id: AuthTestConstants::STATUS_VERIFIED,
      external_id: customer.extid,
    )
    require 'argon2'
    hasher     = Argon2::Password.new(t_cost: 1, m_cost: 5, p_cost: 1)
    auth_db[:account_password_hashes].insert(id: account_id, password_hash: hasher.create(password))
    account_id
  end

  def remove_password(account_id)
    auth_db[:account_password_hashes].where(id: account_id).delete
  end

  def seed_identity(account_id, provider: 'oidc', uid: nil, issuer: 'https://idp.example.com')
    uid ||= "sub-#{SecureRandom.hex(10)}"
    id    = identities.insert(account_id: account_id, provider: provider, uid: uid, issuer: issuer)
    { id: id, uid: uid }
  end

  def clear_body_headers
    header 'Content-Type', nil
    header 'Content-Length', nil
  end

  # Establish an authenticated session via password login.
  def csrf_login(email, password: AuthTestConstants::TEST_PASSWORD)
    clear_body_headers
    header 'Accept', 'application/json'
    get '/auth'
    token = last_response.headers['X-CSRF-Token']

    header 'Content-Type', 'application/json'
    header 'Accept', 'application/json'
    header 'X-CSRF-Token', token if token
    post '/auth/login', JSON.generate(login: email, password: password, shrimp: token)
    expect(last_response.status).to be_between(200, 302),
      "Precondition failed: login for #{email} returned #{last_response.status}: #{last_response.body}"
  end

  def get_identities
    clear_body_headers
    header 'Accept', 'application/json'
    get '/auth/identities'
  end

  # DELETE with a fresh CSRF token (the route is a non-SSO /auth path, so
  # Rack::Protection requires the shrimp token on the unsafe verb).
  def delete_identity(id)
    clear_body_headers
    header 'Accept', 'application/json'
    get '/auth'
    token = last_response.headers['X-CSRF-Token']
    header 'X-CSRF-Token', token if token
    delete "/auth/identities/#{id}"
  end

  def json_body
    JSON.parse(last_response.body)
  end

  # ==========================================================================
  # Authentication gate
  # ==========================================================================

  describe 'authentication required' do
    it 'GET /auth/identities returns 401 when unauthenticated' do
      get_identities
      expect(last_response.status).to eq(401)
      expect(json_body).to include('error')
    end

    it 'DELETE /auth/identities/:id returns 401 when unauthenticated' do
      account_id = seed_account_with_password("solo-#{SecureRandom.hex(6)}@example.com")
      row        = seed_identity(account_id)
      delete_identity(row[:id])
      expect(last_response.status).to eq(401)
      # The row must be untouched.
      expect(identities.where(id: row[:id]).count).to eq(1)
    end
  end

  # ==========================================================================
  # GET — own rows only
  # ==========================================================================

  describe 'GET /auth/identities' do
    it 'returns only the current account rows with masked uid and no created_at' do
      a_email = "a-#{SecureRandom.hex(6)}@example.com"
      b_email = "b-#{SecureRandom.hex(6)}@example.com"
      a_id    = seed_account_with_password(a_email)
      b_id    = seed_account_with_password(b_email)

      a_row1 = seed_identity(a_id, provider: 'oidc')
      a_row2 = seed_identity(a_id, provider: 'entra')
      b_row  = seed_identity(b_id, provider: 'oidc')

      csrf_login(a_email)
      get_identities

      expect(last_response.status).to eq(200)
      body = json_body
      expect(body).to have_key('identities')

      returned_ids = body['identities'].map { |h| h['id'] }
      expect(returned_ids).to contain_exactly(a_row1[:id], a_row2[:id])
      expect(returned_ids).not_to include(b_row[:id])

      row = body['identities'].find { |h| h['id'] == a_row1[:id] }
      expect(row.keys).to match_array(%w[id provider issuer uid])
      expect(row).not_to have_key('created_at')
      expect(row['provider']).to eq('oidc')
      # uid is masked, not the raw subject.
      expect(row['uid']).not_to eq(a_row1[:uid])
      expect(row['uid']).to include('…')
    end
  end

  # ==========================================================================
  # DELETE — ownership scoping (no IDOR)
  # ==========================================================================

  describe 'DELETE /auth/identities/:id' do
    it 'removes an identity that belongs to the caller' do
      email      = "own-#{SecureRandom.hex(6)}@example.com"
      account_id = seed_account_with_password(email)
      keep       = seed_identity(account_id, provider: 'oidc')
      drop       = seed_identity(account_id, provider: 'entra')

      csrf_login(email)
      delete_identity(drop[:id])

      expect(last_response.status).to eq(200)
      expect(json_body).to include('success')
      expect(identities.where(id: drop[:id]).count).to eq(0)
      expect(identities.where(id: keep[:id]).count).to eq(1)
    end

    it 'returns 404 and deletes nothing for a cross-account id (no IDOR)' do
      a_email = "a-#{SecureRandom.hex(6)}@example.com"
      b_email = "b-#{SecureRandom.hex(6)}@example.com"
      a_id    = seed_account_with_password(a_email)
      b_id    = seed_account_with_password(b_email)
      seed_identity(a_id) # A needs an identity so the account is not identity-less
      b_row   = seed_identity(b_id)

      csrf_login(a_email)
      delete_identity(b_row[:id])

      expect(last_response.status).to eq(404)
      # B's identity must be intact — A cannot delete it.
      expect(identities.where(id: b_row[:id]).count).to eq(1)
    end
  end

  # ==========================================================================
  # Last-credential safety
  # ==========================================================================

  describe 'last-credential safety' do
    it 'refuses (409) to remove the final identity of an SSO-only account' do
      email      = "ssoonly-#{SecureRandom.hex(6)}@example.com"
      account_id = seed_account_with_password(email)
      row        = seed_identity(account_id)

      csrf_login(email)
      # Make the account SSO-only: drop the password AFTER login (the session
      # cookie stays valid; has_password? re-queries at delete time).
      remove_password(account_id)

      delete_identity(row[:id])

      expect(last_response.status).to eq(409)
      expect(json_body['error_code']).to eq('last_credential')
      expect(identities.where(id: row[:id]).count).to eq(1),
        'The only sign-in method must not be removed'
    end

    it 'allows removing the final identity when the account has a password' do
      email      = "haspw-#{SecureRandom.hex(6)}@example.com"
      account_id = seed_account_with_password(email)
      row        = seed_identity(account_id)

      csrf_login(email)
      delete_identity(row[:id])

      expect(last_response.status).to eq(200)
      expect(identities.where(id: row[:id]).count).to eq(0)
    end
  end

  # ==========================================================================
  # mask_uid — display masking boundary (unit)
  # ==========================================================================
  #
  # mask_uid (routes/identities.rb) returns '***' for length <= 8 and
  # "#{first4}…#{last4}" otherwise. Exercised directly via a tiny double that
  # includes the route module — no HTTP/DB round-trip needed. Auth::Routes::
  # Identities is loaded during boot (router.rb requires + includes it).

  describe '#mask_uid (boundary)' do
    let(:masker) { Class.new { include Auth::Routes::Identities }.new }

    it 'fully masks a uid of exactly 8 chars (the <= 8 boundary)' do
      expect(masker.send(:mask_uid, 'abcd1234')).to eq('***')
    end

    it 'masks a 9-char uid as first4 + … + last4 (just past the boundary)' do
      expect(masker.send(:mask_uid, 'abcde1234')).to eq('abcd…1234')
    end

    it 'fully masks nil and empty' do
      expect(masker.send(:mask_uid, nil)).to eq('***')
      expect(masker.send(:mask_uid, '')).to eq('***')
    end
  end
end
