# apps/web/auth/spec/integration/full/mfa_awaiting_flag_clear_spec.rb
#
# frozen_string_literal: true

# Regression coverage for issue #3884 — "awaiting_mfa clear on MFA completion
# has no test".
#
# What is under test
# ------------------
# apps/web/auth/config/hooks/mfa.rb, after_two_factor_authentication:
#
#     session['awaiting_mfa'] = false
#
# The flag is the MFA gate: PrepareMfaSession sets session['awaiting_mfa'] =
# true when the password step defers to a second factor, and
# BaseSessionAuthStrategy refuses every request while it reads true. If the
# clear regresses, a user who completes MFA stays locked out of the app.
#
# Two things make that line easy to break silently:
#
#   1. The STRING key is load-bearing. BaseSessionAuthStrategy checks
#      `session['awaiting_mfa'] == true`; a symbol :awaiting_mfa never matches
#      the writer's string key, so the gate would fail OPEN — which is exactly
#      the bug fixed in commit 01352555 (issue #3854), reasoned from code with
#      no test to prove it.
#   2. The line looks redundant. SyncSession#populate_session already deletes
#      both key forms — but it runs inside ErrorHandler.safe_execute, which
#      swallows StandardError. When the sync fails, this line is the ONLY
#      remaining clear. That is its reason to exist, so it is tested here with
#      SyncSession forced to raise.
#
# Why an inline Roda app rather than the mounted /auth app
# --------------------------------------------------------
# MFA is boot-time conditional (config.rb gates Features::MFA + Hooks::MFA on
# Onetime.auth_config.mfa_enabled?) and spec/auth.test.yaml pins `mfa: false`,
# so the booted app has no otp routes at all — which is why
# spec/integration/full/env_toggles/mfa_spec.rb can only assert "route exists"
# and never completes a real OTP auth. This spec boots the full application
# (Valkey, Familia, Auth::Operations) and then mounts a Rodauth app configured
# with the REAL production modules — Auth::Config::Features::MFA and
# Auth::Config::Hooks::MFA/Login — so the hook body executing here is the
# production hook body, not a copy of it.
#
# REQUIREMENTS: Valkey on port 2121 (pnpm run test:database:start).
#
# RUN:
#   AUTHENTICATION_MODE=full AUTH_DATABASE_URL=sqlite::memory: \
#     pnpm run test:rspec apps/web/auth/spec/integration/full/mfa_awaiting_flag_clear_spec.rb

require_relative '../../spec_helper'
require 'rack/test'
require 'rotp'
require 'bcrypt'

require_relative '../../support/auth_test_constants'

RSpec.describe 'MFA completion clears awaiting_mfa (issue #3884)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    # Loads the real Auth::Config (a Rodauth::Auth subclass) along with
    # Auth::Config::Features::*, Auth::Config::Hooks::* and Auth::Operations::*,
    # and connects Familia to the test datastore. See the note in
    # pending_plan_intent_flow_spec.rb: never fabricate the Auth::Config
    # constant here — doing so poisons boot for every spec in the process.
    boot_onetime_app
  end

  let(:db) { create_test_database }
  let(:password) { 'correct horse battery staple' }
  let(:email) { "mfa-clear-#{SecureRandom.hex(6)}@integration-test.example.com" }

  let(:account_id) do
    id = db[:accounts].insert(email: email, status_id: AuthTestConstants::STATUS_VERIFIED)
    db[:account_password_hashes].insert(id: id, password_hash: BCrypt::Password.create(password))
    id
  end

  # Rodauth app wired with the production MFA feature config and the production
  # login/MFA hooks. Feature-enable order mirrors config.rb: :json before :otp,
  # so Hooks::MFA's before_otp_setup_route runs after the json feature has
  # populated the setup secrets.
  let(:app) do
    app_db = db

    Class.new(Roda) do
      plugin :sessions, secret: SecureRandom.hex(64)
      plugin :json
      plugin :json_parser
      plugin :halt

      plugin :rodauth do
        db app_db
        enable :base, :json, :login, :logout
        only_json? true
        login_column :email
        hmac_secret SecureRandom.hex(32)

        # Production MFA wiring: enables two_factor_base/otp/recovery_codes and
        # sets otp params, HMAC keys, failure limits (config/features/mfa.rb).
        Auth::Config::Features::MFA.configure(self)

        # Production hooks. Login.configure owns after_login, whose MFA branch
        # calls PrepareMfaSession (the writer of awaiting_mfa); MFA.configure
        # owns after_two_factor_authentication (the clear under test).
        Auth::Config::Hooks::Login.configure(self)
        Auth::Config::Hooks::MFA.configure(self)
      end

      route do |r|
        r.rodauth

        # Reads the session as the NEXT request sees it, after the cookie
        # round-trip — the state BaseSessionAuthStrategy would act on.
        r.get 'session-probe' do
          {
            'awaiting_mfa' => session['awaiting_mfa'],
            'authenticated' => session['authenticated'],
          }
        end
      end
    end
  end

  # Enrolls OTP through Rodauth's real two-step JSON otp-setup flow and returns
  # the shared secret the authenticator would hold, leaving the account logged
  # out and ready for a fresh MFA login.
  let(:otp_secret) do
    account_id
    status, = login!
    raise "otp enrollment: login failed (#{status})" unless status == 200

    # Step 1 returns the secrets with a 422 (JSON HMAC flow).
    _, setup = post_json('/otp-setup', {})
    secret   = setup['otp_setup']
    raise "otp enrollment: no otp_setup in #{setup.inspect}" if secret.to_s.empty?

    # Step 2 verifies a real TOTP code and stores the key.
    status, body = post_json(
      '/otp-setup',
      otp_setup: secret,
      otp_raw_secret: setup['otp_raw_secret'],
      otp_code: ROTP::TOTP.new(secret).now,
      password: password,
    )
    raise "otp enrollment: setup failed (#{status}) #{body.inspect}" unless status == 200

    # Rodauth stamps last_use at enrollment and otp_update_last_use refuses a
    # second use inside the same 30s interval, so a code generated now would be
    # rejected as a replay. Backdate the stamp instead of sleeping. Plain
    # Time.now, not Time.now.utc: the comparison is against the database's
    # CURRENT_TIMESTAMP as Sequel renders it (local by default), and a UTC
    # wall-clock lands in the future on a machine behind UTC.
    db[:account_otp_keys].where(id: account_id).update(last_use: Time.now - 300)

    post_json('/logout', {})
    clear_cookies

    secret
  end

  # The in-request session hash. Symbol and string keys are still distinct here
  # (Roda's JSON session serializer stringifies both on the way out), so this is
  # the only place a symbol-key regression on the clear is observable.
  def rack_session
    last_request.env['rack.session']
  end

  def parsed_body
    JSON.parse(last_response.body)
  rescue JSON::ParserError
    {}
  end

  def post_json(path, body)
    post(path, body.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json')
    [last_response.status, parsed_body]
  end

  def login!
    post_json('/login', login: email, password: password)
  end

  def session_probe
    get('/session-probe', {}, 'HTTP_ACCEPT' => 'application/json')
    parsed_body
  end

  def current_otp_code(secret)
    ROTP::TOTP.new(secret).now
  end

  before do
    # Delivery is best-effort in production (safe_execute) and not under test;
    # stubbing keeps the example off RabbitMQ and its async-thread fallback.
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)
  end

  describe 'a login that requires MFA' do
    it 'sets awaiting_mfa true under the string key and defers the session sync' do
      otp_secret

      status, body = login!

      expect(status).to eq(200)
      expect(body['mfa_required']).to be(true)
      expect(rack_session.fetch('awaiting_mfa')).to be(true)
      # SyncSession is deferred until the second factor, so the app-session
      # authenticated marker must not be set yet.
      expect(rack_session['authenticated']).to be_nil
    end
  end

  describe 'completing MFA with a valid TOTP code' do
    it 'clears awaiting_mfa under the string key and finishes the session sync' do
      secret = otp_secret
      login!
      expect(rack_session.fetch('awaiting_mfa')).to be(true)

      status, = post_json('/otp-auth', otp_code: current_otp_code(secret))

      expect(status).to eq(200)
      expect(rack_session.fetch('awaiting_mfa')).to be(false)
      # A symbol key would leave BaseSessionAuthStrategy's string read unmatched.
      expect(rack_session.keys.grep(Symbol)).not_to include(:awaiting_mfa)
      # Second factor recorded, and the deferred SyncSession has now run.
      expect(rack_session['authenticated_by']).to include('totp')
      expect(rack_session['authenticated']).to be(true)
    end

    it 'leaves the gate cleared on the next request, after the cookie round-trip' do
      secret = otp_secret
      login!
      post_json('/otp-auth', otp_code: current_otp_code(secret))

      expect(session_probe).to include('awaiting_mfa' => false, 'authenticated' => true)
    end
  end

  # The reason line 219 of hooks/mfa.rb is kept rather than deleted as
  # redundant: SyncSession's own clear runs inside safe_execute, so a raising
  # sync leaves the hook's assignment as the only thing between the user and a
  # permanent awaiting-MFA lockout.
  describe 'completing MFA when SyncSession raises' do
    it 'still clears awaiting_mfa under the string key' do
      secret = otp_secret # enroll before stubbing: enrollment's login syncs

      allow(Auth::Operations::SyncSession).to receive(:call)
        .and_raise(Sequel::DatabaseConnectionError, 'simulated datastore failure')

      login!
      expect(rack_session.fetch('awaiting_mfa')).to be(true)

      status, = post_json('/otp-auth', otp_code: current_otp_code(secret))

      # safe_execute swallows the failure, so MFA itself still succeeds.
      expect(status).to eq(200)
      expect(rack_session.fetch('awaiting_mfa')).to be(false)
      expect(rack_session.keys.grep(Symbol)).not_to include(:awaiting_mfa)
      # Proof the clear came from the hook and not from SyncSession: the sync's
      # other writes are absent.
      expect(rack_session['authenticated']).to be_nil
    end

    it 'leaves the gate cleared on the next request' do
      secret = otp_secret

      allow(Auth::Operations::SyncSession).to receive(:call)
        .and_raise(Sequel::DatabaseConnectionError, 'simulated datastore failure')

      login!
      post_json('/otp-auth', otp_code: current_otp_code(secret))

      expect(session_probe).to include('awaiting_mfa' => false, 'authenticated' => nil)
    end
  end

  # Counterweight: proves the assertions above have teeth — the flag is not
  # simply always false by the end of an otp-auth request.
  describe 'a failed TOTP attempt' do
    it 'leaves awaiting_mfa true' do
      otp_secret
      login!

      status, = post_json('/otp-auth', otp_code: '000000')

      expect(status).not_to eq(200)
      expect(rack_session.fetch('awaiting_mfa')).to be(true)
      expect(session_probe['awaiting_mfa']).to be(true)
    end
  end
end
