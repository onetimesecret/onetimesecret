# apps/web/auth/spec/integration/oauth_idp_security_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration
# =============================================================================
#
# OAuth2/OIDC IdP — security boundary specs. Issue #3104, task 10.
#
# Companion to oauth_idp_protocol_spec.rb (loop conformance) and
# oauth_idp_endpoints_spec.rb (per-endpoint input validation). This file
# focuses specifically on attack-surface scenarios: cross-client grant abuse,
# expired/revoked grant rejection, scope binding at token issuance, and
# /userinfo authorization-token soundness (openid scope, forged JWTs).
#
# Out of scope (already covered or unreachable — quoted gem refs inline):
#   - code reuse, PKCE verifier mismatch (covered by protocol_spec)
#   - mismatched redirect_uri at /token (covered by endpoints_spec.rb:309)
#   - PKCE downgrade attack (`code_challenge_method=plain` at /token):
#       oauth_pkce.rb:75 reads the method off the grant DB row, not the
#       request param — request-side method is ignored at redemption.
#   - HTTPS-only redirect_uri enforcement: in dev/test the gem permits http://
#     by default (oauth_valid_uri_schemes includes "http"); enforcement is a
#     gem config concern, not an IdP wiring concern.
#   - Issuer pinning negative test: Onetime.boot! is memoized once per
#     process, so OAUTH_ISSUER cannot be perturbed mid-suite.
#
# REQUIREMENTS:
# - Valkey on port 2121 (pnpm run test:database:start)
# - AUTHENTICATION_MODE=full
# - AUTH_OAUTH_ENABLED=true (set below before spec_helper)
# - OAUTH_JWT_RSA_PRIVATE_KEY (generated below if absent)
# - OAUTH_SP_DEV_CLIENT_SECRET (generated below if absent)
#
# RUN:
#   source .env.test && \
#     bundle exec rspec apps/web/auth/spec/integration/oauth_idp_security_spec.rb
#
# Lives at integration/ (not integration/full/) for the same reason the
# sibling specs do: path-keyed MockAuthConfig under integration/full/
# does not expose oauth_enabled? and would turn the IdP feature off at boot.
# =============================================================================

require 'openssl'
require 'securerandom'

# Pre-boot env must run BEFORE spec_helper. Boot is one-shot — first writer
# wins on AUTH_OAUTH_ENABLED.
ENV['AUTH_OAUTH_ENABLED']        = 'true'
ENV['OAUTH_ISSUER']              ||= 'http://localhost:3000/auth'
ENV['OAUTH_JWT_RSA_PRIVATE_KEY'] ||= OpenSSL::PKey::RSA.new(2048).to_pem
ENV['OAUTH_SP_DEV_CLIENT_SECRET'] ||= "spec-sp-secret-#{SecureRandom.hex(12)}"

ENV['AUTHENTICATION_MODE'] ||= 'full'
ENV['RACK_ENV']            ||= 'test'

require_relative '../spec_helper'

require 'base64'
require 'bcrypt'
require 'cgi'
require 'digest'
require 'json'
require 'jwt'

RSpec.describe 'OAuth/OIDC IdP security boundaries', type: :integration, sqlite_database: true do
  # Primary (canonical dev) client — same values as the seed inserter.
  let(:client_id)     { 'onetimesecret-sp-dev' }
  let(:client_secret) { ENV.fetch('OAUTH_SP_DEV_CLIENT_SECRET') }
  let(:redirect_uri)  { 'http://localhost:3000/auth/sso/local/callback' }
  let(:issuer)        { ENV.fetch('OAUTH_ISSUER') }

  # Secondary client — used to assert cross-client isolation. Created in
  # before(:all) below.
  let(:other_client_id)     { 'onetimesecret-sp-spec-other' }
  let(:other_client_secret) { @other_client_secret }
  let(:other_redirect_uri)  { 'http://localhost:3000/auth/sso/spec-other/callback' }

  # Shared PKCE pair.
  let(:code_verifier) { SecureRandom.urlsafe_base64(64).tr('=', '') }
  let(:code_challenge) do
    Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)
  end

  before(:all) do
    boot_onetime_app

    unless Onetime.auth_config.oauth_enabled?
      raise <<~MSG
        OAuth IdP feature is not enabled in the booted Onetime app. Run this
        spec in isolation, or load it before any other integration spec that
        boots without AUTH_OAUTH_ENABLED.
      MSG
    end

    # Re-seed the canonical dev SP client if missing (a sibling spec may
    # have truncated oauth_applications).
    unless auth_db[:oauth_applications].where(client_id: 'onetimesecret-sp-dev').any?
      require 'auth/initializers/seed_dev_oauth_client'
      Auth::Initializers::SeedDevOAuthClient.new.execute(nil)
    end

    # Seed the secondary client used by cross-client isolation tests.
    # Mirrors the column shape from SeedDevOAuthClient#execute so we
    # exercise the same authentication code path.
    @other_client_secret = "spec-other-secret-#{SecureRandom.hex(12)}"
    if auth_db[:oauth_applications].where(client_id: 'onetimesecret-sp-spec-other').empty?
      auth_db[:oauth_applications].insert(
        account_id: nil,
        name: 'OneTimeSecret SP spec-other',
        description: 'Secondary SP client for cross-client isolation tests.',
        redirect_uri: 'http://localhost:3000/auth/sso/spec-other/callback',
        client_id: 'onetimesecret-sp-spec-other',
        client_secret: BCrypt::Password.create(@other_client_secret),
        scopes: 'openid email profile',
        subject_type: 'public',
        id_token_signed_response_alg: 'RS256',
        token_endpoint_auth_method: 'client_secret_basic',
        grant_types: 'authorization_code refresh_token',
        response_types: 'code',
      )
    end
  end

  let(:created_account_ids) { [] }
  let(:created_grant_ids)   { [] }

  after do
    auth_db[:oauth_grants].where(id: created_grant_ids).delete    unless created_grant_ids.empty?
    auth_db[:accounts].where(id: created_account_ids).delete     unless created_account_ids.empty?
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────

  def create_verified_account
    email = "oauth-sec-#{SecureRandom.hex(6)}@example.com"
    id = auth_db[:accounts].insert(
      email: email,
      status_id: 2,
      created_at: Time.now,
      updated_at: Time.now,
    )
    created_account_ids << id
    { id: id, email: email }
  end

  # Seeds an oauth_grants row for the named client_id. Accepts overrides for
  # the security-relevant columns: scopes, expires_in (for expiry tests),
  # revoked_at (for revocation tests), challenge/method.
  def seed_grant(account_id:, for_client_id: client_id, for_redirect_uri: redirect_uri,
                 scopes: 'openid email profile',
                 challenge: code_challenge, method: 'S256',
                 expires_at: Time.now + 300,
                 revoked_at: nil)
    app_id = auth_db[:oauth_applications].where(client_id: for_client_id).get(:id)
    raise "no oauth_applications row for client_id=#{for_client_id}" if app_id.nil?

    code = SecureRandom.urlsafe_base64(32)
    row = {
      account_id: account_id,
      oauth_application_id: app_id,
      code: code,
      redirect_uri: for_redirect_uri,
      expires_in: expires_at,
      scopes: scopes,
      created_at: Time.now,
      code_challenge: challenge,
      code_challenge_method: method,
      # 'offline' is the migration default for the access_type column. The
      # cross-client refresh-token test seeds a refresh_token directly, so
      # we don't depend on /token generating one here.
      access_type: 'offline',
    }
    row[:revoked_at] = revoked_at if revoked_at

    grant_id = auth_db[:oauth_grants].insert(row)
    created_grant_ids << grant_id
    { id: grant_id, code: code, app_id: app_id }
  end

  def basic_auth_header(id:, secret:)
    'Basic ' + Base64.strict_encode64("#{id}:#{secret}")
  end

  def post_token(form, basic_id: client_id, basic_secret: client_secret)
    header 'Host', 'localhost:3000'
    header 'Authorization', basic_auth_header(id: basic_id, secret: basic_secret)
    header 'Accept', 'application/json'
    post '/auth/token', form
  end

  # Normalizes 4xx/302 OAuth errors to a hash with 'error' / 'error_description'.
  def parse_error(response)
    body = response.body.to_s
    return JSON.parse(body) if body.start_with?('{')

    if response.headers['Location']
      query = URI.parse(response.headers['Location']).query.to_s
      Hash[query.split('&').map { |kv| kv.split('=', 2).then { |k, v| [k, CGI.unescape(v.to_s)] } }]
    else
      { 'error' => 'unknown', 'raw' => body[0, 200] }
    end
  end

  # ─── Cross-client isolation ──────────────────────────────────────────────
  describe 'Cross-client grant isolation' do
    let(:account) { create_verified_account }

    # Per oauth_authorization_code_grant.rb:147, /token filters the grant
    # lookup by `oauth_application[oauth_applications_id_column]` (the
    # authenticated client). So a code issued to client A is invisible to
    # client B at redemption time and surfaces as invalid_grant.
    it 'rejects an authorization code issued to client A when redeemed by client B' do
      grant = seed_grant(account_id: account[:id], for_client_id: client_id)

      # Authenticate as the OTHER client; supply A's code.
      post_token(
        {
          grant_type:    'authorization_code',
          code:          grant[:code],
          redirect_uri:  redirect_uri,
          code_verifier: code_verifier,
        },
        basic_id:     other_client_id,
        basic_secret: other_client_secret,
      )

      expect(last_response.status).to be_between(400, 499),
        "Expected 4xx, got #{last_response.status}: #{last_response.body[0, 300]}"
      err = parse_error(last_response)
      expect(err['error']).to match(/invalid_grant|invalid_request/),
        "Expected invalid_grant/invalid_request, got: #{err.inspect}"
    end

    # Per oauth_base.rb:620, oauth_grant_by_refresh_token_ds filters by the
    # authenticated client's application_id. Refresh tokens are therefore
    # bound to the issuing client. We seed the refresh_token + token columns
    # directly to skip the /token round-trip — the security boundary we are
    # asserting is the application_id filter on /token, not refresh-token
    # issuance.
    it 'rejects a refresh_token issued for client A when presented by client B' do
      grant = seed_grant(account_id: account[:id], for_client_id: client_id)

      # Mark this grant as "already redeemed" by clearing the code and writing
      # a refresh_token into the row — matches the post-/token shape described
      # in migrations/009_oauth_grants.rb (lines 10-13).
      refresh_token = "rt-#{SecureRandom.urlsafe_base64(32)}"
      auth_db[:oauth_grants].where(id: grant[:id]).update(
        code: nil,
        token: "at-#{SecureRandom.urlsafe_base64(32)}",
        refresh_token: refresh_token,
      )

      # Present client A's refresh token under client B's credentials.
      post_token(
        { grant_type: 'refresh_token', refresh_token: refresh_token },
        basic_id:     other_client_id,
        basic_secret: other_client_secret,
      )

      expect(last_response.status).to be_between(400, 499),
        "Expected 4xx, got #{last_response.status}: #{last_response.body[0, 300]}"
      err = parse_error(last_response)
      expect(err['error']).to match(/invalid_grant|invalid_request/),
        "Expected invalid_grant/invalid_request, got: #{err.inspect}"
    end
  end

  # ─── Expiry and revocation ──────────────────────────────────────────────
  describe 'Grant lifecycle enforcement' do
    let(:account) { create_verified_account }

    # valid_oauth_grant_ds (oauth_base.rb:596) filters out rows whose
    # expires_in is in the past. A grant 60s past should produce no row,
    # which surfaces as invalid_grant at /token.
    it 'rejects an authorization code whose expires_in is in the past' do
      grant = seed_grant(account_id: account[:id],
                          expires_at: Time.now - 60)

      post_token({
        grant_type:    'authorization_code',
        code:          grant[:code],
        redirect_uri:  redirect_uri,
        code_verifier: code_verifier,
      })

      expect(last_response.status).to be_between(400, 499),
        "Expected 4xx, got #{last_response.status}: #{last_response.body[0, 300]}"
      expect(parse_error(last_response)['error']).to match(/invalid_grant|invalid_request/)
    end

    # valid_oauth_grant_ds also filters revoked_at IS NULL. A grant with
    # revoked_at set must not be redeemable.
    it 'rejects an authorization code whose revoked_at is set' do
      grant = seed_grant(account_id: account[:id],
                          revoked_at: Time.now)

      post_token({
        grant_type:    'authorization_code',
        code:          grant[:code],
        redirect_uri:  redirect_uri,
        code_verifier: code_verifier,
      })

      expect(last_response.status).to be_between(400, 499),
        "Expected 4xx, got #{last_response.status}: #{last_response.body[0, 300]}"
      expect(parse_error(last_response)['error']).to match(/invalid_grant|invalid_request/)
    end

    # Even with a structurally-valid (signature-verified, unexpired) JWT
    # access token, /userinfo re-checks the underlying grant via
    # valid_oauth_grant_ds (oidc.rb:142-147). Revoking the grant after the
    # token was issued must invalidate /userinfo access.
    it 'rejects /userinfo for an issued access token whose grant has been revoked' do
      grant = seed_grant(account_id: account[:id])
      post_token({
        grant_type:    'authorization_code',
        code:          grant[:code],
        redirect_uri:  redirect_uri,
        code_verifier: code_verifier,
      })
      expect(last_response.status).to eq(200), "Setup /token failed: #{last_response.body}"

      access_token = JSON.parse(last_response.body).fetch('access_token')

      # Revoke the grant row out from under the access token. The JWT itself
      # remains cryptographically valid; the runtime DB check is the gate.
      auth_db[:oauth_grants].where(id: grant[:id]).update(revoked_at: Time.now)

      header 'Host', 'localhost:3000'
      header 'Authorization', "Bearer #{access_token}"
      get '/auth/userinfo'

      expect(last_response.status).to eq(401), "Body: #{last_response.body}"
      expect(parse_error(last_response)['error']).to eq('invalid_token')
    end
  end

  # ─── Scope binding at /token ────────────────────────────────────────────
  describe 'Scope binding' do
    let(:account) { create_verified_account }

    # oauth_jwt.rb:102 sets the access token's `scope` claim from
    # `oauth_grant[oauth_grants_scopes_column]` — i.e. the scope captured at
    # /authorize, not the request param at /token. Sending a wider `scope`
    # at /token must not expand the issued access token.
    it 'the access_token scope claim equals the granted scope, not a wider /token scope param' do
      grant = seed_grant(account_id: account[:id], scopes: 'openid email')

      # Send a deliberately-wider scope at /token.
      header 'Host', 'localhost:3000'
      header 'Authorization', basic_auth_header(id: client_id, secret: client_secret)
      header 'Accept', 'application/json'
      post '/auth/token', {
        grant_type:    'authorization_code',
        code:          grant[:code],
        redirect_uri:  redirect_uri,
        code_verifier: code_verifier,
        scope:         'openid email profile admin', # narrower in grant; would be escalation
      }

      expect(last_response.status).to eq(200), "Body: #{last_response.body}"
      access_token = JSON.parse(last_response.body).fetch('access_token')

      # Decode JWT (verify signature with the configured RSA public key).
      public_key = OpenSSL::PKey::RSA.new(ENV.fetch('OAUTH_JWT_RSA_PRIVATE_KEY')).public_key
      payload, _h = JWT.decode(access_token, public_key, true, algorithm: 'RS256')

      expect(payload['scope']).to eq('openid email'),
        "Access token scope widened beyond grant: #{payload['scope'].inspect}"
      # And in particular: no 'admin' or 'profile' leaked from the /token request.
      expect(payload['scope'].to_s.split(' ')).not_to include('admin')
      expect(payload['scope'].to_s.split(' ')).not_to include('profile')
    end
  end

  # ─── /userinfo authorization-token soundness ────────────────────────────
  describe '/userinfo bearer-token verification' do
    let(:account) { create_verified_account }

    # oidc.rb:128 — userinfo route throws invalid_token unless the access
    # token's scope claim contains "openid". A grant with no openid scope
    # produces a JWT whose scope claim lacks "openid"; /userinfo must reject.
    it 'rejects an access token whose scope does not include "openid"' do
      grant = seed_grant(account_id: account[:id], scopes: 'email profile')
      post_token({
        grant_type:    'authorization_code',
        code:          grant[:code],
        redirect_uri:  redirect_uri,
        code_verifier: code_verifier,
      })
      expect(last_response.status).to eq(200), "Setup /token failed: #{last_response.body}"

      access_token = JSON.parse(last_response.body).fetch('access_token')

      header 'Host', 'localhost:3000'
      header 'Authorization', "Bearer #{access_token}"
      get '/auth/userinfo'

      expect(last_response.status).to eq(401), "Body: #{last_response.body}"
      expect(parse_error(last_response)['error']).to eq('invalid_token')
    end

    # Defense-in-depth check against algorithm confusion. The gem decodes
    # access tokens via JWT.decode with algorithms: [RS256] whitelisted
    # (oauth_jwt_base.rb:450). A token forged with alg:none must be rejected
    # even though it parses as a JWT and claims a valid sub/aud. Also covers
    # the typ=at+jwt header check (oauth_jwt.rb:60).
    it 'rejects a forged JWT with alg:none at /userinfo' do
      # Construct a fake "JWT" with alg=none. Two base64url-encoded segments
      # plus an empty signature segment — the canonical alg:none shape.
      header_seg = Base64.urlsafe_encode64(
        JSON.generate(alg: 'none', typ: 'at+jwt'),
        padding: false,
      )
      payload_seg = Base64.urlsafe_encode64(
        JSON.generate(
          iss: issuer,
          sub: account[:id].to_s,
          aud: client_id,
          client_id: client_id,
          scope: 'openid email',
          iat: Time.now.to_i,
          exp: Time.now.to_i + 300,
          jti: SecureRandom.uuid,
        ),
        padding: false,
      )
      forged = "#{header_seg}.#{payload_seg}."

      header 'Host', 'localhost:3000'
      header 'Authorization', "Bearer #{forged}"
      get '/auth/userinfo'

      expect(last_response.status).to eq(401), "Body: #{last_response.body}"
      expect(parse_error(last_response)['error']).to eq('invalid_token')
    end
  end
end
