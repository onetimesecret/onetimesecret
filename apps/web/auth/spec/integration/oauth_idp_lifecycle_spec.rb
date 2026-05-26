# apps/web/auth/spec/integration/oauth_idp_lifecycle_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration
# =============================================================================
#
# OAuth2/OIDC IdP — token lifecycle and claim correctness. Issue #3104.
#
# Complements oauth_idp_protocol_spec.rb (end-to-end SP→IdP loop) and
# oauth_idp_endpoints_spec.rb (per-endpoint error responses). This file
# focuses on the *protocol invariants downstream consumers actually depend
# on*:
#
#   - Refresh-token grant lifecycle (rotation in/out)
#   - Access-token expiration (DB-row gate)
#   - Access-token revocation (oauth_grants.revoked_at)
#   - ID-token claim completeness (iss/aud/sub/iat/exp/nonce/auth_time)
#   - ID-token signature kid matches a JWKS key
#   - /userinfo claim parity with id_token for the same grant
#   - Scope downscoping: id_token + /userinfo respect grant scopes
#   - PKCE method=plain: gate is at /authorize (NOT /token) — finding
#
# Things deliberately NOT in scope here:
#   - Discovery doc shape (covered by oauth_idp_endpoints_spec.rb)
#   - PKCE S256 happy path (covered by oauth_idp_protocol_spec.rb)
#   - Code-reuse rejection (covered by oauth_idp_protocol_spec.rb)
#   - JWKS key rotation tolerance — no second key is provisioned in our
#     config (apps/web/auth/config/features/oauth.rb:239), so this is
#     untestable here. Flagged in commit body as follow-up.
#
# REQUIREMENTS:
# - Valkey on port 2121 (pnpm run test:database:start)
# - AUTH_DATABASE_URL set
# - AUTHENTICATION_MODE=full
# - AUTH_OAUTH_ENABLED=true (set below)
# - OAUTH_JWT_RSA_PRIVATE_KEY (generated below if absent)
# - OAUTH_SP_DEV_CLIENT_SECRET (generated below if absent)
#
# RUN:
#   bundle exec rspec apps/web/auth/spec/integration/oauth_idp_lifecycle_spec.rb
#
# This spec lives at integration/ (not integration/full/) for the same reason
# the two existing oauth_idp_* specs do — the path-keyed MockAuthConfig under
# integration/full/ doesn't expose oauth_enabled? and would disable the IdP
# feature at boot.
# =============================================================================

require 'openssl'
require 'securerandom'

# Pre-boot env: identical shape to oauth_idp_protocol_spec.rb so the trio can
# be invoked in a single rspec call (boot is memoized, first writer wins).
ENV['AUTH_OAUTH_ENABLED']        = 'true'
ENV['OAUTH_ISSUER']              ||= 'http://localhost:3000/auth'
ENV['OAUTH_JWT_RSA_PRIVATE_KEY'] ||= OpenSSL::PKey::RSA.new(2048).to_pem
ENV['OAUTH_SP_DEV_CLIENT_SECRET'] ||= "spec-sp-secret-#{SecureRandom.hex(12)}"

ENV['AUTHENTICATION_MODE'] ||= 'full'
ENV['RACK_ENV']            ||= 'test'

require_relative '../spec_helper'

require 'base64'
require 'cgi'
require 'digest'
require 'json'
require 'jwt'

RSpec.describe 'OAuth/OIDC IdP token lifecycle', type: :integration, sqlite_database: true do
  let(:client_id)     { 'onetimesecret-sp-dev' }
  let(:client_secret) { ENV.fetch('OAUTH_SP_DEV_CLIENT_SECRET') }
  let(:redirect_uri)  { 'http://localhost:3000/auth/sso/local/callback' }
  let(:issuer)        { ENV.fetch('OAUTH_ISSUER') }

  let(:code_verifier) { SecureRandom.urlsafe_base64(64).tr('=', '') }
  let(:code_challenge) do
    Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)
  end

  # The RSA private key the IdP signs ID tokens / JWT access tokens with.
  let(:rsa_private)   { OpenSSL::PKey::RSA.new(ENV.fetch('OAUTH_JWT_RSA_PRIVATE_KEY')) }
  let(:rsa_public)    { rsa_private.public_key }

  before(:all) do
    boot_onetime_app

    unless Onetime.auth_config.oauth_enabled?
      raise <<~MSG
        OAuth IdP feature is not enabled in the booted Onetime app. Run this
        spec in isolation, or before any other integration spec that boots
        without AUTH_OAUTH_ENABLED.
      MSG
    end

    unless auth_db[:oauth_applications].where(client_id: 'onetimesecret-sp-dev').any?
      require 'auth/initializers/seed_dev_oauth_client'
      Auth::Initializers::SeedDevOAuthClient.new.execute(nil)
    end

    # FINDING (seed bug): apps/web/auth/initializers/seed_dev_oauth_client.rb:92
    # sets the dev SP's grant_types column to 'authorization_code' only — no
    # 'refresh_token'. supported_grant_type? (oauth_base.rb:706-717) prefers
    # the application's grant_types column over oauth_grant_types_supported
    # (which DOES include refresh_token per features/oauth.rb:212). End
    # result: /token rejects every refresh_token grant with invalid_request
    # for this SP, regardless of scope or config.
    #
    # Widen here so the refresh-token examples can exercise their target
    # protocol path. Flagged in the commit body as a real seed fix needed.
    auth_db[:oauth_applications]
      .where(client_id: 'onetimesecret-sp-dev')
      .update(grant_types: 'authorization_code refresh_token')
  end

  let(:created_account_ids) { [] }
  let(:created_grant_ids)   { [] }

  after do
    auth_db[:oauth_grants].where(id: created_grant_ids).delete    unless created_grant_ids.empty?
    auth_db[:accounts].where(id: created_account_ids).delete     unless created_account_ids.empty?
  end

  # ─── Helpers (mirror the existing two specs to keep this file independently
  #     runnable; the cost is small duplication).

  def create_verified_account
    email = "oauth-lc-#{SecureRandom.hex(6)}@example.com"
    id = auth_db[:accounts].insert(
      email: email,
      status_id: 2, # Verified
      created_at: Time.now,
      updated_at: Time.now,
    )
    created_account_ids << id
    { id: id, email: email }
  end

  # Seeds an oauth_grant row simulating a completed /authorize. The defaults
  # match what the gem would write for an `openid email profile` request with
  # S256 PKCE and a fixed nonce.
  def seed_authorization_code(account_id:, scopes: 'openid email profile',
                              challenge: code_challenge, method: 'S256',
                              nonce: nil, expires_at: Time.now + 300)
    app_id = auth_db[:oauth_applications].where(client_id: client_id).get(:id)
    code = SecureRandom.urlsafe_base64(32)

    grant_id = auth_db[:oauth_grants].insert(
      account_id: account_id,
      oauth_application_id: app_id,
      code: code,
      redirect_uri: redirect_uri,
      expires_in: expires_at,
      scopes: scopes,
      created_at: Time.now,
      code_challenge: challenge,
      code_challenge_method: method,
      access_type: 'online',
      nonce: nonce,
    )
    created_grant_ids << grant_id
    { id: grant_id, code: code }
  end

  def basic_auth_header(id: client_id, secret: client_secret)
    'Basic ' + Base64.strict_encode64("#{id}:#{secret}")
  end

  # Posts an auth-code redemption. Returns the parsed JSON body, with the raw
  # response available via last_response for status assertions.
  def post_token_for_code(code, verifier: code_verifier, redirect: redirect_uri)
    header 'Host', 'localhost:3000'
    header 'Authorization', basic_auth_header
    header 'Accept', 'application/json'
    post '/auth/token', {
      grant_type:    'authorization_code',
      code:          code,
      redirect_uri:  redirect,
      code_verifier: verifier,
    }
    JSON.parse(last_response.body)
  end

  # Posts a refresh-token grant. Returns the parsed JSON body.
  def post_token_for_refresh(refresh_token)
    header 'Host', 'localhost:3000'
    header 'Authorization', basic_auth_header
    header 'Accept', 'application/json'
    post '/auth/token', {
      grant_type:    'refresh_token',
      refresh_token: refresh_token,
    }
    JSON.parse(last_response.body)
  end

  # GETs /userinfo with a Bearer token. Returns last_response unchanged so
  # the caller can assert status before parsing.
  def get_userinfo(access_token)
    header 'Host', 'localhost:3000'
    header 'Authorization', "Bearer #{access_token}"
    get '/auth/userinfo'
    last_response
  end

  # Convenience: redeem a freshly seeded grant for a verified account and
  # hand back {access_token, refresh_token, id_token, grant_id}. Used by
  # specs that don't care about the redemption step itself.
  #
  # NOTE on `with_refresh`: when the :oidc feature is enabled (it is in our
  # config), the gem ONLY issues a refresh_token when `offline_access` is in
  # the granted scopes — see oidc.rb:769-773. Default left off so callers
  # only opt-in when they actually need it.
  def redeem_fresh_grant(scopes: 'openid email profile', nonce: nil, with_refresh: false)
    scopes = "#{scopes} offline_access" if with_refresh && !scopes.split.include?('offline_access')
    account = create_verified_account
    grant   = seed_authorization_code(account_id: account[:id], scopes: scopes, nonce: nonce)
    body    = post_token_for_code(grant[:code])
    raise "redeem_fresh_grant failed: #{last_response.status} #{last_response.body}" unless last_response.status == 200

    body.merge('account' => account, 'grant_id' => grant[:id])
  end

  # ─── Refresh-token grant ─────────────────────────────────────────────────
  describe 'Refresh-token grant' do
    it 'omits refresh_token when scope does NOT include offline_access (gem behavior)' do
      # FINDING: with :oidc enabled, oidc.rb:769-773 wraps the base
      # generate_token in a check that ANDs `should_generate_refresh_token`
      # with `scopes.include?("offline_access")`. So a plain
      # `openid email profile` grant returns NO refresh_token. The OAuth-only
      # path (without :oidc) would issue one unconditionally for code grants.
      # SPs that need offline access must request `offline_access` explicitly.
      result = redeem_fresh_grant # default scope, no offline_access
      expect(result['access_token']).to be_a(String)
      expect(result['refresh_token']).to be_nil,
        "Expected no refresh_token absent offline_access; got: #{result.inspect}"
    end

    it 'issues a refresh_token when scope includes offline_access' do
      result = redeem_fresh_grant(with_refresh: true)
      expect(result['refresh_token']).to be_a(String).and(satisfy { |s| !s.empty? })
      expect(result['access_token']).to  be_a(String).and(satisfy { |s| !s.empty? })
    end

    it 'redeems a refresh_token for a new access_token (happy path)' do
      result     = redeem_fresh_grant(with_refresh: true)
      refresh_v1 = result.fetch('refresh_token')

      body = post_token_for_refresh(refresh_v1)
      expect(last_response.status).to eq(200), "Body: #{last_response.body}"
      expect(body['access_token']).to be_a(String).and(satisfy { |s| !s.empty? })
      expect(body['token_type'].to_s.downcase).to eq('bearer')
      # Note: we don't assert access_token != access_v1. The gem derives jti
      # from SHA256(aud:iat) (oauth_jwt_base.rb:98-106) and uses Time.now.to_i
      # for iat, so two redemptions in the same wallclock second produce
      # byte-identical JWTs. This is a known JWT-with-1s-resolution quirk,
      # not a protocol invariant we can portably assert on.
    end

    it 'rotates the refresh_token on each redemption (oauth_refresh_token_protection_policy="rotation")' do
      # apps/web/auth/config/features/oauth.rb:144 sets the policy to
      # "rotation". Under that policy the gem invokes _generate_refresh_token
      # at oauth_base.rb:685 on every refresh, overwriting the column with a
      # new SHA256 hash. The new refresh_token in the response MUST differ
      # from the one we sent.
      result     = redeem_fresh_grant(with_refresh: true)
      refresh_v1 = result.fetch('refresh_token')

      body = post_token_for_refresh(refresh_v1)
      expect(last_response.status).to eq(200), "Body: #{last_response.body}"

      refresh_v2 = body['refresh_token']
      expect(refresh_v2).to be_a(String).and(satisfy { |s| !s.empty? })
      expect(refresh_v2).not_to eq(refresh_v1), 'expected refresh_token to rotate'
    end

    it 'rejects reuse of the previous refresh_token after rotation (invalid_grant)' do
      # Gem mechanic (oauth_base.rb:619-637 + 674): the lookup hashes the
      # supplied refresh_token with SHA256 and queries
      # oauth_grants_refresh_token_hash_column. After rotation overwrote the
      # row, the old plaintext hashes to a value no longer present → the
      # dataset is empty → invalid_grant. Note this is NOT done via
      # revoked_at; rotation overwrites in place.
      result     = redeem_fresh_grant(with_refresh: true)
      refresh_v1 = result.fetch('refresh_token')

      first_body  = post_token_for_refresh(refresh_v1)
      expect(last_response.status).to eq(200), "First refresh failed: #{first_body.inspect}"

      second_body = post_token_for_refresh(refresh_v1)
      expect(last_response.status).to be_between(400, 499),
        "Expected refresh-reuse to be rejected; got #{last_response.status} #{second_body.inspect}"
      expect(second_body['error']).to eq('invalid_grant'),
        "Expected invalid_grant; got: #{second_body.inspect}"
    end

    it 'rejects an unknown refresh_token (invalid_grant)' do
      body = post_token_for_refresh("not-a-real-token-#{SecureRandom.hex(16)}")
      expect(last_response.status).to be_between(400, 499)
      expect(body['error']).to eq('invalid_grant'), "Got: #{body.inspect}"
    end
  end

  # ─── Access-token expiration ─────────────────────────────────────────────
  describe 'Access-token expiration' do
    # Access tokens in our setup are JWTs (oauth_jwt_access_tokens=true by
    # gem default; :oidc depends on :oauth_jwt). The JWT itself carries
    # iat+exp; /userinfo decodes it with JWT.decode AND then looks the grant
    # up via valid_oauth_grant_ds, which filters by the DB
    # `expires_in > CURRENT_TIMESTAMP`. Either gate can fail it.

    it 'FINDING: does NOT enforce JWT exp at /userinfo (json-jwt branch + buggy AND-chain)' do
      # FINDING: rodauth-oauth's json-jwt branch (oauth_jwt_base.rb:217-285)
      # is the active code path when both gems are loaded. Its
      # post-decode validation at lines 269-278 is an AND-chain
      # (`if cond_exp && cond_nbf && cond_iat && cond_iss && cond_aud && cond_jti`),
      # so it only `return`s nil when EVERY claim is bad simultaneously.
      # A JWT with past `exp` but valid iss/aud/iat/jti slips through.
      # Independently, JSON::JWT.decode does NOT enforce exp either.
      #
      # Compounding: /userinfo's DB grant lookup (oidc.rb:142 ->
      # valid_oauth_grant_ds) still gates by oauth_grants.expires_in. In
      # practice, the DB row's expires_in is bumped to "now + 3600" every
      # time /token issues a token, so the DB gate works on the issued
      # token's lifetime. But a forged-but-validly-signed JWT with future
      # iat and past exp gets accepted — surface as a gem bug to upstream.
      #
      # This assertion documents the current behavior so a future gem
      # upgrade that fixes the AND-chain will (intentionally) break this
      # test and prompt revisit.
      account = create_verified_account
      grant   = seed_authorization_code(account_id: account[:id])
      redeemed = post_token_for_code(grant[:code])
      expect(last_response.status).to eq(200), "Body: #{last_response.body}"
      live_access_token = redeemed.fetch('access_token')

      # Decode without verification to learn the real claims.
      live_payload, live_header = JWT.decode(live_access_token, rsa_public, true,
                                             algorithm: 'RS256')
      past_payload = live_payload.merge(
        'iat' => Time.now.to_i - 7200,
        'exp' => Time.now.to_i - 3600, # 1 hour ago
      )
      past_token = JWT.encode(past_payload, rsa_private, 'RS256',
                              live_header.merge('typ' => 'at+jwt'))

      get_userinfo(past_token)
      # Documenting current (broken) behavior. If this starts failing with
      # 401, the gem fixed the AND-chain — update this expectation.
      expect(last_response.status).to eq(200),
        "If status is 401, the gem now correctly enforces JWT exp at /userinfo. " \
        "Update this test and re-evaluate. Body: #{last_response.body[0, 200]}"
    end

    it 'rejects /userinfo when the DB grant row is expired (DB-row gate)' do
      # /userinfo line 142 in oidc.rb looks up the grant via
      # valid_oauth_grant_ds (oauth_base.rb:596-602) which filters
      # `expires_in >= CURRENT_TIMESTAMP`. Forcing the row's expires_in into
      # the past while leaving the JWT intact tests THIS gate specifically.
      account = create_verified_account
      grant   = seed_authorization_code(account_id: account[:id])
      redeemed = post_token_for_code(grant[:code])
      expect(last_response.status).to eq(200), "Body: #{last_response.body}"
      access_token = redeemed.fetch('access_token')

      # /token's UPDATE just refreshed expires_in to "now + 3600". Push it
      # back to "1 hour ago" so the grant row no longer satisfies the
      # valid_oauth_grant_ds filter.
      auth_db[:oauth_grants].where(id: grant[:id])
        .update(expires_in: Time.now - 3600)

      get_userinfo(access_token)
      expect(last_response.status).to eq(401),
        "Expected 401 with stale grant row; got #{last_response.status}: #{last_response.body}"
    end
  end

  # ─── Revocation surface ──────────────────────────────────────────────────
  describe 'Token revocation surface' do
    it 'invalidates /userinfo after the grant row is revoked' do
      # /revoke is covered for protocol shape in the endpoints spec; here we
      # just need the downstream consequence: once oauth_grants.revoked_at is
      # set, /userinfo must reject the bearer (valid_oauth_grant_ds filters
      # revoked_at IS NULL).
      account = create_verified_account
      grant   = seed_authorization_code(account_id: account[:id])
      redeemed = post_token_for_code(grant[:code])
      expect(last_response.status).to eq(200), "Body: #{last_response.body}"
      access_token = redeemed.fetch('access_token')

      # Sanity: token works first.
      get_userinfo(access_token)
      expect(last_response.status).to eq(200), "Pre-revoke userinfo failed: #{last_response.body}"

      # Revoke directly in the DB to skip a second /revoke round-trip (its
      # behavior is asserted elsewhere; we want the downstream effect here).
      auth_db[:oauth_grants].where(id: grant[:id]).update(revoked_at: Time.now)

      get_userinfo(access_token)
      expect(last_response.status).to eq(401),
        "Expected 401 after revoke; got #{last_response.status}: #{last_response.body}"
    end
  end

  # ─── ID-token claim completeness ─────────────────────────────────────────
  describe 'ID-token claims' do
    let(:fixed_nonce) { "nonce-#{SecureRandom.hex(8)}" }

    # Decodes the id_token from a redemption result, returning [payload, header].
    def decode_id_token(result)
      JWT.decode(result.fetch('id_token'), rsa_public, true,
                 algorithm: 'RS256',
                 verify_iat: false) # iat is exercised in its own example
    end

    it 'sets iat to roughly "now" and exp to iat + oauth_access_token_expires_in' do
      # Gem: oauth_jwt.rb:114 sets `iat: Time.now.to_i`; line 131 sets
      # `exp: issued_at + oauth_access_token_expires_in`. Our config pins
      # the latter to 3600 (apps/web/auth/config/features/oauth.rb:137).
      # NOTE: jwt_claims is shared by both access tokens and id_token claims
      # (oidc.rb id_token_claims calls jwt_claims first), so iat/exp on the
      # id_token follow the same formula.
      before_t = Time.now.to_i
      result   = redeem_fresh_grant
      after_t  = Time.now.to_i + 1

      payload, _h = decode_id_token(result)

      expect(payload['iat']).to be_between(before_t, after_t),
        "iat=#{payload['iat']} outside [#{before_t}, #{after_t}]"
      expect(payload['exp']).to eq(payload['iat'] + 3600),
        "exp(#{payload['exp']}) != iat(#{payload['iat']}) + 3600"
    end

    it 'sets iss=issuer, aud=client_id, sub=account_id' do
      # aud: oauth_jwt_audience returns oauth_application[client_id] when
      # is_authorization_server? (oauth_jwt_base.rb:45-46). sub: by default
      # the public subject is the account row's id as a string (jwt_subject
      # at oidc.rb:363+).
      result = redeem_fresh_grant
      payload, _h = decode_id_token(result)

      expect(payload['iss']).to eq(issuer)
      expect(payload['aud']).to eq(client_id)
      expect(payload['sub']).to eq(result['account'][:id].to_s)
    end

    it 'propagates the grant nonce into the id_token' do
      # oidc.rb:562 sets claims[:nonce] from
      # oauth_grants[oauth_grants_nonce_column] when present. Seeded
      # directly here — we don't go through /authorize.
      account = create_verified_account
      grant   = seed_authorization_code(account_id: account[:id], nonce: fixed_nonce)
      body    = post_token_for_code(grant[:code])
      expect(last_response.status).to eq(200), "Body: #{last_response.body}"

      payload, _h = JWT.decode(body.fetch('id_token'), rsa_public, true,
                                algorithm: 'RS256', verify_iat: false)
      expect(payload['nonce']).to eq(fixed_nonce)
    end

    it 'omits nonce when the grant has none' do
      # Same hook as above — nil column means the gem skips setting the
      # claim (oidc.rb:562 guards with `if oauth_grant[..nonce]`).
      result = redeem_fresh_grant
      payload, _h = decode_id_token(result)
      expect(payload).not_to have_key('nonce')
    end

    it 'omits auth_time for accounts without an active session row (#3233)' do
      # rodauth-oauth's id_token_claims (oidc.rb:567) unconditionally calls
      # `get_oidc_account_last_login_at(account_id).to_i`. With no
      # active_sessions row the helper returns nil, nil.to_i==0, and the
      # gem would emit `auth_time: 0` — a NumericDate of 1970-01-01, which
      # OIDC Core §2 does not allow ("Time when the End-User authentication
      # occurred").
      #
      # apps/web/auth/config/features/oauth.rb overrides id_token_claims to
      # drop :auth_time when it serializes to 0. A non-zero auth_time from
      # an active session still passes through.
      result = redeem_fresh_grant
      payload, _h = decode_id_token(result)
      expect(payload).not_to have_key('auth_time'),
        "Expected auth_time to be omitted absent an active_sessions row; got #{payload['auth_time'].inspect}"
    end

    it 'signs with a kid advertised in JWKS' do
      # The gem uses the json-jwt branch when both gems are present
      # (oauth_jwt_base.rb:132). Signing uses `JSON::JWK.new(key)` for the
      # signing JWK (line 188), and JWKS uses `jwk_export` which is also
      # `JSON::JWK.new(key)` (line 152-154). The kids must match.
      #
      # IMPORTANT: don't precompute `JWT::JWK.new(key).kid` — that's the
      # ruby-jwt thumbprint, which uses a different algorithm from json-jwt
      # and won't match what the gem emits. Just assert membership in the
      # JWKS set.
      result = redeem_fresh_grant
      _payload, jwt_header = decode_id_token(result)

      id_token_kid = jwt_header['kid']
      expect(id_token_kid).to be_a(String).and(satisfy { |s| !s.empty? }),
        "id_token has no kid header: #{jwt_header.inspect}"

      header 'Host', 'localhost:3000'
      get '/auth/jwks'
      expect(last_response.status).to eq(200)
      jwks_kids = JSON.parse(last_response.body)['keys'].map { |k| k['kid'] }
      expect(jwks_kids).to include(id_token_kid),
        "JWKS kids=#{jwks_kids.inspect} did not include id_token kid=#{id_token_kid.inspect}"
    end
  end

  # ─── /userinfo claim parity with id_token ───────────────────────────────
  describe '/userinfo claim parity with id_token' do
    it 'returns the same sub/email/email_verified as the id_token for the same grant' do
      # oidc.rb /userinfo (line 159) calls fill_with_account_claims, the
      # same helper that id_token claim-filling uses (oidc.rb:543). So for
      # the same scopes the user-facing claims should match the id_token.
      result = redeem_fresh_grant
      id_payload, _h = JWT.decode(result.fetch('id_token'), rsa_public, true,
                                   algorithm: 'RS256', verify_iat: false)

      access_token = result.fetch('access_token')
      get_userinfo(access_token)
      expect(last_response.status).to eq(200), "Body: #{last_response.body}"
      userinfo = JSON.parse(last_response.body)

      expect(userinfo['sub']).to eq(id_payload['sub'])
      expect(userinfo['email']).to eq(id_payload['email']).and(eq(result['account'][:email]))
      expect(userinfo['email_verified']).to eq(id_payload['email_verified']).and(eq(true))
    end
  end

  # ─── Scope downscoping ──────────────────────────────────────────────────
  describe 'Scope downscoping' do
    it 'omits email claims from id_token and /userinfo when scope=openid only' do
      # The gem doesn't downscope between /authorize and /token — it reads
      # what's stored in oauth_grants.scopes. With only `openid` granted,
      # OIDC_SCOPES_MAP & oauth_scopes = ∅ (oidc.rb:539), so
      # fill_with_account_claims for the id_token gets skipped. /userinfo
      # likewise removes "openid" from the scope list and gets no remaining
      # claim-bearing scopes (oidc.rb:134-159).
      account = create_verified_account
      grant   = seed_authorization_code(account_id: account[:id], scopes: 'openid')
      body    = post_token_for_code(grant[:code])
      expect(last_response.status).to eq(200), "Body: #{last_response.body}"

      payload, _h = JWT.decode(body.fetch('id_token'), rsa_public, true,
                                algorithm: 'RS256', verify_iat: false)
      expect(payload).not_to have_key('email'),
        "openid-only grant leaked email into id_token: #{payload.inspect}"
      expect(payload).not_to have_key('email_verified')

      access_token = body.fetch('access_token')
      get_userinfo(access_token)
      expect(last_response.status).to eq(200), "Body: #{last_response.body}"
      userinfo = JSON.parse(last_response.body)
      expect(userinfo).not_to have_key('email'),
        "openid-only grant leaked email into /userinfo: #{userinfo.inspect}"
      expect(userinfo['sub']).not_to be_nil # sub is unconditional
    end
  end

  # ─── PKCE method=plain — gate location finding ──────────────────────────
  describe 'PKCE method=plain at /token (gem-behavior finding)' do
    it 'accepts a seeded plain-method grant at /token (verifier == challenge)' do
      # FINDING: rodauth-oauth gates `code_challenge_method == "plain"` only
      # at /authorize via validate_pkce_challenge_params
      # (oauth_pkce.rb:60-64), which compares against
      # oauth_pkce_challenge_method (default "S256"). At /token, the check
      # is check_valid_grant_challenge? (oauth_pkce.rb:72-85), which
      # explicitly accepts "plain" by comparing challenge==verifier.
      #
      # Implication: a row inserted directly into oauth_grants with
      # code_challenge_method='plain' bypasses the /authorize-time gate and
      # /token will happily issue tokens. Any flow that creates oauth_grants
      # rows by means other than the gem's own /authorize handler (e.g. an
      # admin tool, a migration helper, a future hybrid SSO bridge) must
      # treat 'plain' as untrusted explicitly. The protocol invariant is
      # preserved end-to-end because /authorize is the only way external
      # SPs reach the row; this assertion documents the *internal* gap.
      #
      # If we ever ship admin tooling that writes oauth_grants, we should
      # either add a server-side rejection in create_token_from_authorization_code
      # (oauth_pkce.rb:46-58) or constrain inserts at the DB layer.
      account = create_verified_account
      plain_verifier = SecureRandom.urlsafe_base64(48).tr('=', '')
      grant   = seed_authorization_code(
        account_id: account[:id],
        challenge:  plain_verifier, # plain: challenge IS the verifier
        method:     'plain',
      )

      header 'Host', 'localhost:3000'
      header 'Authorization', basic_auth_header
      header 'Accept', 'application/json'
      post '/auth/token', {
        grant_type:    'authorization_code',
        code:          grant[:code],
        redirect_uri:  redirect_uri,
        code_verifier: plain_verifier,
      }

      expect(last_response.status).to eq(200),
        "Expected /token to accept seeded plain-method grant (gem bug surface). " \
        "Got #{last_response.status}: #{last_response.body}"
    end
  end
end
