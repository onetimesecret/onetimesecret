# apps/web/auth/spec/config/features/mfa_provisioning_uri_spec.rb
#
# frozen_string_literal: true

# Regression coverage for issue #3431 — "MFA QR code encodes wrong secret".
#
# Root cause
# ----------
# With otp_keys_use_hmac? enabled, the secret an authenticator app must use is
# the HMAC'd key (Rodauth's otp_user_key, surfaced in the JSON otp-setup
# response as otp_setup), NOT the raw key (otp_raw_secret, which exists only for
# the setup handshake). The SPA used to rebuild the otpauth:// URI itself and,
# on the HMAC path, encoded the raw key — so scanned codes never matched what
# the server validates, while the manually-displayed otp_setup key worked.
#
# Fix
# ---
# The backend now emits Rodauth's authoritative otp_provisioning_uri as
# `provisioning_uri` in the otp-setup response (see
# apps/web/auth/config/hooks/mfa.rb), and the SPA renders it directly. Because
# otp_provisioning_uri is built from the brand-configured otp_issuer, the issuer
# in the QR also stays correct without any client-side reconstruction.
#
# These tests exercise the mechanism through the real otp-setup route, in the
# real feature-enable order (json before otp), with a before_otp_setup_route
# hook mirroring the production one. They assert that:
#   1. provisioning_uri is present and embeds the otp_setup (HMAC'd) secret,
#   2. a code derived from provisioning_uri completes setup, and
#   3. a code derived from otp_raw_secret is rejected (the original bug).

require_relative '../../spec_helper'
require 'rack/test'
require 'rotp'
require 'bcrypt'
require 'cgi'

require_relative '../../support/auth_test_constants'
include AuthTestConstants

RSpec.describe 'MFA otp-setup provisioning_uri (issue #3431)' do
  include Rack::Test::Methods

  let(:db) { create_test_database }
  let(:password) { 'correct horse battery staple' }

  let(:account_id) do
    id = db[:accounts].insert(email: 'mfa-user@example.com', status_id: STATUS_VERIFIED)
    db[:account_password_hashes].insert(id: id, password_hash: BCrypt::Password.create(password))
    id
  end

  let(:app) do
    app_db = db
    # Build the Roda app inline (rather than via the create_rodauth_app helper)
    # so we can add :json_parser — the SPA posts JSON request bodies, and
    # only_json? rejects non-JSON requests. The feature-enable order mirrors
    # production: :json (base.rb) is enabled before :otp (mfa.rb), which is what
    # makes the configured before_otp_setup_route hook run AFTER Rodauth's json
    # feature has populated the setup secrets.
    Class.new(Roda) do
      plugin :sessions, secret: SecureRandom.hex(64)
      plugin :json
      plugin :json_parser
      plugin :halt

      plugin :rodauth do
        db app_db
        enable :base, :json, :login, :logout, :two_factor_base, :otp, :recovery_codes
        only_json? true
        login_column :email
        hmac_secret SecureRandom.hex(32)
        otp_issuer 'OneTimeSecret'
        otp_setup_param 'otp_setup'
        otp_setup_raw_param 'otp_raw_secret'
        otp_auth_param 'otp_code'
        otp_keys_use_hmac? true
        auto_add_recovery_codes? true
        recovery_codes_limit 4

        # Production hook logic from apps/web/auth/config/hooks/mfa.rb.
        before_otp_setup_route do
          if otp_keys_use_hmac? && (raw_secret = json_response[otp_setup_raw_param])
            otp_tmp_key(raw_secret)
            json_response[:provisioning_uri] = otp_provisioning_uri
          end
        end
      end

      route { |r| r.rodauth }
    end
  end

  def json_post(path, body)
    post(path, body.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json')
    [last_response.status, JSON.parse(last_response.body)]
  end

  def secret_in(provisioning_uri)
    CGI.parse(URI.parse(provisioning_uri).query)['secret'].first
  end

  before do
    account_id # create the account
    status, = json_post('/login', login: 'mfa-user@example.com', password: password)
    expect(status).to eq(200)
  end

  it 'returns a provisioning_uri that embeds the otp_setup (HMAC) secret, not the raw secret' do
    status, body = json_post('/otp-setup', {})

    expect(status).to eq(422) # JSON HMAC flow returns the secrets with a 422
    expect(body).to include('otp_setup', 'otp_raw_secret', 'provisioning_uri')
    expect(body['otp_setup']).not_to eq(body['otp_raw_secret'])

    embedded = secret_in(body['provisioning_uri'])
    expect(embedded).to eq(body['otp_setup'])
    expect(embedded).not_to eq(body['otp_raw_secret'])
    expect(body['provisioning_uri']).to start_with('otpauth://totp/OneTimeSecret:')
  end

  it 'accepts a TOTP code derived from provisioning_uri to complete setup' do
    _, setup = json_post('/otp-setup', {})
    code     = ROTP::TOTP.new(secret_in(setup['provisioning_uri'])).now

    status, body = json_post(
      '/otp-setup',
      otp_setup: setup['otp_setup'],
      otp_raw_secret: setup['otp_raw_secret'],
      otp_code: code,
      password: password,
    )

    expect(status).to eq(200)
    expect(body).to have_key('success')
    expect(db[:account_otp_keys].where(id: account_id).count).to eq(1)
  end

  it 'rejects a TOTP code derived from otp_raw_secret (the original bug)' do
    _, setup   = json_post('/otp-setup', {})
    wrong_code = ROTP::TOTP.new(setup['otp_raw_secret']).now

    status, = json_post(
      '/otp-setup',
      otp_setup: setup['otp_setup'],
      otp_raw_secret: setup['otp_raw_secret'],
      otp_code: wrong_code,
      password: password,
    )

    expect(status).not_to eq(200)
    expect(db[:account_otp_keys].where(id: account_id).count).to eq(0)
  end
end
