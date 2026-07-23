# spec/unit/auth/sso_link_confirm_route_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'sequel'
require 'json'
require 'roda'
require 'rack/test'
require 'auth/routes/sso_link_confirm'

# Route-level tests for Auth::Routes::SsoLinkConfirm (#3840 Phase 4).
#
# A minimal Roda app includes the route module and drives it with Rack::Test,
# against a REAL in-memory SQLite (accounts / account_identities) and a REAL
# Familia token — the same real-DB posture as the bind_sso_identity spec. Rodauth
# is a small fake exposing only the surface the route uses (db, account_from_login,
# login, session, respond_to?). This locks the request parsing and the
# op-result -> HTTP/JSON mapping. The success path's session-establishing
# rodauth.login is stubbed to return a login body (the real Rodauth THROWS it); the
# genuine throw + after_login wiring is exercised by the Wave 2 full-boot spec.
RSpec.describe Auth::Routes::SsoLinkConfirm, type: :rack do
  include Rack::Test::Methods

  let(:db)         { build_auth_db }
  let(:identities) { db[:account_identities] }

  let(:account_id) { 42 }
  let(:email)      { 'user@example.com' }
  let(:provider)   { 'google' }
  let(:issuer)     { 'https://accounts.google.com' }
  let(:uid)        { 'sub-123' }
  let(:sid)        { 'a' * 64 }

  let(:tokens)   { [] }
  let(:otp)      { false }
  let(:account_found) { true }
  let(:rodauth)  { FakeRodauth.new(db: db, otp: otp, account_found: account_found) }

  # ── minimal Rodauth stand-in ──────────────────────────────────────────────
  class FakeRodauth
    attr_reader :db, :login_calls, :account_from_login_calls

    def initialize(db:, otp: false, account_found: true)
      @db                       = db
      @otp                      = otp
      @account_found            = account_found
      @login_calls              = []
      @account_from_login_calls = []
    end

    def respond_to?(name, include_all = false)
      return @otp if name == :otp_auth_route

      super
    end

    def session
      nil # -> route's current-sid resolver rescues to nil (soft check skipped)
    end

    def account_from_login(login)
      @account_from_login_calls << login
      @account_found
    end

    def login(auth_type)
      @login_calls << auth_type
      { success: true } # real Rodauth THROWS this; returning it is fine for the mapping test
    end
  end

  def null_logger
    @null_logger ||= Class.new do
      def method_missing(*); nil; end
      def respond_to_missing?(*); true; end
    end.new
  end

  def app
    rd  = rodauth
    log = null_logger
    Class.new(Roda) do
      plugin :json
      plugin :halt
      include Auth::Routes::SsoLinkConfirm
      define_method(:rodauth) { rd }
      define_method(:auth_logger) { log }
      route do |r|
        handle_sso_link_confirm_routes(r)
      end
    end
  end

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
    db
  end

  def seed_account(id: account_id, account_email: email, external_id: nil)
    db[:accounts].insert(id: id, email: account_email, external_id: external_id, status_id: 2)
    id
  end

  def issue_token(**overrides)
    record = Onetime::SsoLinkVerification.issue(
      provider: provider,
      uid: uid,
      email: overrides.fetch(:email, email),
      account_id: overrides.fetch(:account_id, account_id),
      sid: sid,
      password_watermark: overrides.fetch(:password_watermark, 0),
      issuer: issuer,
    )
    tokens << record.token
    record.token
  end

  def json_post(token)
    post '/sso-link-confirm', JSON.generate({ token: token }), { 'CONTENT_TYPE' => 'application/json' }
  end

  def body
    JSON.parse(last_response.body)
  end

  after do
    tokens.each { |t| Onetime::SsoLinkVerification.load(t)&.delete! rescue nil }
  end

  describe 'GET /sso-link-confirm/:token (consent display)' do
    it 'returns ONLY provider + claimed email and does NOT consume the token' do
      token = issue_token

      get "/sso-link-confirm/#{token}"

      expect(last_response.status).to eq(200)
      expect(body).to eq('provider' => provider, 'email' => email)
      # Display must never consume — the token is still loadable.
      expect(Onetime::SsoLinkVerification.load(token)).not_to be_nil
    end

    it 'returns 404 link_expired for an unknown token' do
      get '/sso-link-confirm/nope'
      expect(last_response.status).to eq(404)
      expect(body['error_code']).to eq('link_expired')
    end
  end

  describe 'POST /sso-link-confirm (confirm)' do
    it 'rejects a missing token with 400 invalid_request' do
      post '/sso-link-confirm', JSON.generate({}), { 'CONTENT_TYPE' => 'application/json' }
      expect(last_response.status).to eq(400)
      expect(body['error_code']).to eq('invalid_request')
    end

    it 'rejects an already-consumed / unknown token with 401 link_expired' do
      json_post('does-not-exist')
      expect(last_response.status).to eq(401)
      expect(body['error_code']).to eq('link_expired')
    end

    it 'maps an identity owned by a different account to 409 link_conflict' do
      seed_account
      other = seed_account(id: 999, account_email: 'other@example.com')
      identities.insert(provider: provider, issuer: issuer, uid: uid, account_id: other)

      json_post(issue_token)
      expect(last_response.status).to eq(409)
      expect(body['error_code']).to eq('link_conflict')
    end

    it 'maps a credential-change watermark advance to 409 link_invalidated' do
      wm_email = "route-wm-#{SecureRandom.hex(4)}@example.com"
      customer = Onetime::Customer.create!(wm_email)
      customer.last_password_update! 200
      seed_account(account_email: wm_email, external_id: customer.extid)

      json_post(issue_token(email: wm_email, password_watermark: 100))
      expect(last_response.status).to eq(409)
      expect(body['error_code']).to eq('link_invalidated')
    ensure
      customer&.delete!
    end

    it 'on success binds, logs in via Rodauth, and returns the login response' do
      seed_account
      token = issue_token

      json_post(token)

      expect(last_response.status).to eq(200)
      expect(body).to eq('success' => true)
      # Session established through Rodauth's own machinery, as the passwordless account.
      expect(rodauth.account_from_login_calls).to eq([email])
      expect(rodauth.login_calls).to eq(['sso_link_confirm'])
      # The identity was actually bound.
      expect(identities.where(provider: provider, issuer: issuer, uid: uid).count).to eq(1)
    end

    context 'when the account is no longer loginable at login time' do
      let(:account_found) { false } # rodauth.account_from_login returns nil/false

      it 'returns 401 link_expired (the op bound, but login cannot proceed)' do
        seed_account

        json_post(issue_token)
        expect(last_response.status).to eq(401)
        expect(body['error_code']).to eq('link_expired')
      end
    end
  end
end
