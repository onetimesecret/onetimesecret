# apps/web/auth/spec/integration/full_mfa/omniauth_connect_email_auth_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode + AUTH_EMAIL_AUTH_ENABLED=true — DEDICATED LANE)
# =============================================================================
#
# Issue: #3849 — "remembered and email-authenticated sessions cannot mint an
# intent" (Initiation and re-authentication row of the tenant Connect
# acceptance matrix, docs/authentication/per-domain-sso.md).
#
# WHAT IT LOCKS IN, through the REAL magic-link login route on a tenant host:
#   1. POST /auth/email-login-request mails a link on the tenant host, and
#      POST /auth/email-login with the emailed key completes a login whose
#      session is bound to the tenant surface and whose primary is
#      'email_auth' — with NO recent-reauth proof (hooks/login.rb records
#      proof only for RecentReauth::LOCAL_PRIMARIES; mailbox possession is
#      a recovery-class ceremony, NIST SP 800-63B-4 3.1.3.1).
#   2. connect=1 on that session is refused at the request phase: 302 to the
#      re-authentication view, no intent, :omniauth_connect_reauth_required.
#   3. POST /auth/reauth with the account's password on the SAME session
#      records a proof, after which initiation mints an intent and the
#      callback binds — so the refusal was about the primary, not the session.
#
# WHY A DEDICATED LANE: Auth::Config is one-shot per process
# (apps/web/auth/docs/auth-config-one-shot.md) and the shared full-mode lanes
# keep email_auth OFF (spec/auth.test.yaml). This directory runs in its own
# process via `tests/lanes/run full-mfa`, whose env exports
# AUTH_EMAIL_AUTH_ENABLED=true alongside AUTH_MFA_ENABLED=true; the mock auth
# config a :full_auth_mode boot reads (spec/support/auth_mode_helpers.rb)
# honours that env. The :full_auth_mode tag is set EXPLICITLY because the
# path-derived tag only matches /integration/full/.
#
# The mechanism-level twin of this file (the LOCAL_PRIMARIES guard driven
# through the password route with a stubbed primary) lives in
# integration/full/omniauth_connect_link_spec.rb, where email_auth cannot be
# mounted.
#
# REQUIREMENTS:
# - Valkey running on port 2163: pnpm run test:database:start
#
# RUN:
#   tests/lanes/run full-mfa
# or directly (fresh process required):
#   RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL=sqlite::memory: \
#     ORGS_SSO_ENABLED=true AUTH_MFA_ENABLED=true AUTH_EMAIL_AUTH_ENABLED=true \
#     LANG=en_US.UTF-8 bundle exec rspec \
#     apps/web/auth/spec/integration/full_mfa/omniauth_connect_email_auth_spec.rb
# =============================================================================

# Load-time, before the suite's first boot, for the same reason
# support/mfa_flow_helper.rb sets AUTH_MFA_ENABLED: the lane already exports
# it; this makes a direct single-file invocation work and means the file
# cannot boot without the feature it exists to exercise.
ENV['AUTH_EMAIL_AUTH_ENABLED'] = 'true'

require_relative '../../spec_helper'
require_relative '../../support/mfa_flow_helper'
require_relative '../../support/oauth_flow_helper'
require 'onetime/operations/sessions/store'

RSpec.describe 'Tenant Connect after a magic-link login (#3849)',
  :full_auth_mode, :oauth_flow, type: :integration do
  include MfaFlowHelper
  include OAuthFlowHelper

  include_context 'domains enabled'

  # Hard-fail (not skip), mirroring MfaFlowHelper's OTP guard: this file
  # exists to cover the magic-link primary, so a boot without the feature is
  # harness breakage.
  before(:all) do
    next if Auth::Config.method_defined?(:email_auth_route)

    raise 'Rodauth email_auth feature not loaded — this suite must boot with ' \
          'AUTH_EMAIL_AUTH_ENABLED=true in a fresh process (run via ' \
          '`tests/lanes/run full-mfa`; Auth::Config is one-shot)'
  end

  def current_sid
    rack_mock_session.cookie_jar['onetime.session']
  end

  def session_blob(sid)
    db    = Familia.dbclient
    dbkey = Onetime::Operations::Sessions::Store.find_key(db, sid)
    raise "No session blob stored for sid #{sid.inspect}" unless dbkey

    Onetime::Operations::Sessions::Store.load_data(db, dbkey, codec: Onetime::SessionCodec.from_config)
  end

  def initiate_sso_connect(host)
    clear_body_headers
    header 'Host', host
    post '/auth/sso/oidc', { connect: '1' }
  end

  # The emailed key, lifted out of the delivered text body the way a mail
  # client would find it. The link is composed by Rodauth's token_link on the
  # PUBLIC host (config/overrides/public_base_url.rb), route 'email-login'.
  def emailed_login_key(delivered)
    expect(delivered.size).to eq(1), "expected one delivered email, got #{delivered.size}"
    body = delivered.first[:body].to_s
    link = body[%r{https?://\S+?/email-login\?key=[^\s"<]+}]
    expect(link).not_to be_nil, "no /email-login link in the delivered body:\n#{body[0, 600]}"
    [link, CGI.parse(URI.parse(link).query).fetch('key').first]
  end

  it 'refuses connect on a magic-link session, then admits it after a password re-authentication' do
    host       = "email-connect-#{SecureRandom.hex(6)}.tenant.example.com"
    email      = unique_test_email('tenant-connect-email')
    uid        = "email-connect-sub-#{SecureRandom.hex(8)}"
    account_id = seed_account_with_password(email)
    tenant     = setup_oauth_test_domain(host)
    customer   = Onetime::Customer.find_by_extid(auth_db[:accounts].where(id: account_id).get(:external_id))
    Onetime::OrganizationMembership.ensure_membership(
      tenant[:org], customer, role: 'member', domain_scope_id: tenant[:domain].objid, provisioning_source: 'sso',
    )
    # email_auth_enabled: the tenant must opt into magic links too
    # (SigninConfig.resolve_email_auth_enabled ANDs it with the install flag).
    Onetime::CustomDomain::SigninConfig.create!(
      domain_id: tenant[:domain].identifier, enabled: true, signin_enabled: true, sso_enabled: true,
      email_auth_enabled: true,
    )
    # TXT-verified: Auth::PublicHost composes email links on a custom host only
    # once ownership is proven; unverified stays on the canonical host.
    tenant[:domain].verified = true
    tenant[:domain].save
    surface = { 'kind' => 'custom', 'id' => tenant[:domain].identifier }

    # The delivery seam (Auth::Config::Email::Delivery hands the rendered mail
    # to the publisher as a plain hash).
    delivered = []
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw) do |mail, **_kwargs|
      delivered << mail
      true
    end
    allow(Auth::Logging).to receive(:log_auth_event).and_call_original

    # --- the real magic-link login, on the tenant host ---------------------
    header 'Host', host
    csrf_json_post('/auth/email-login-request', login: email)
    expect(last_response.status).to eq(200),
      "email-login-request: #{last_response.status} #{last_response.body}"
    link, key = emailed_login_key(delivered)
    expect(URI.parse(link).host).to eq(host)

    csrf_json_post('/auth/email-login', key: key)
    expect(last_response.status).to eq(200), "email-login: #{last_response.status} #{last_response.body}"
    expect(last_request.env['rack.session']['account_id']).to eq(account_id)

    sid  = current_sid
    blob = session_blob(sid)
    expect(blob[Onetime::SessionSurface::KEY]).to eq(surface)
    expect(blob['auth_method']).to eq('email_auth')
    expect(Onetime::SessionSidecar.exists?(sid, Onetime::RecentReauth::KEY)).to be(false),
      'A magic-link login must not record a recent-reauth proof'

    setup_mock_auth(email: unique_test_email('asserted-victim'), uid: uid)
    begin
      # --- connect=1 on the mailbox-proof session: refused ----------------
      initiate_sso_connect(host)
      skip 'OmniAuth route not registered (OIDC discovery not available at boot)' if last_response.status == 404
      expect(last_response.status).to eq(302)
      expect(last_response.location.to_s).to include(Auth::Config::Hooks::OmniAuth.connect_reauth_redirect),
        "Expected a redirect to re-authentication, got: #{last_response.location.inspect}"
      expect(Onetime::SessionSidecar.exists?(sid, 'sso_connect_intent')).to be(false)
      expect(Onetime::SessionSidecar.exists?(sid, Onetime::RecentReauth::KEY)).to be(false)
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:omniauth_connect_reauth_required, hash_including(provider: 'oidc', account_id: account_id))

      # --- the same session, re-authenticated with the local credential ----
      csrf_json_post('/auth/reauth', method: 'password', password: AuthTestConstants::TEST_PASSWORD)
      expect(last_response.status).to eq(200), "reauth: #{last_response.status} #{last_response.body}"
      expect(current_sid).to eq(sid)
      expect(Onetime::SessionSidecar.read(sid, Onetime::RecentReauth::KEY)).to include(
        'account_id' => account_id, 'surface' => surface, 'methods' => %w[password],
      )

      initiate_sso_connect(host)
      expect(last_response.status).to eq(302)
      expect(last_response.location.to_s).not_to include(Auth::Config::Hooks::OmniAuth::REAUTH_PATH)
      expect(Onetime::SessionSidecar.exists?(sid, 'sso_connect_intent')).to be(true)
      expect(Onetime::SessionSidecar.exists?(sid, Onetime::RecentReauth::KEY)).to be(false)

      clear_body_headers
      header 'Host', host
      post '/auth/sso/oidc/callback'
      expect(last_response.status).to eq(302)
      expect(identities.where(provider: 'oidc', uid: uid).all)
        .to contain_exactly(hash_including(account_id: account_id))
      expect(Onetime::SessionSidecar.exists?(sid, 'sso_connect_intent')).to be(false)
    ensure
      teardown_mock_auth
    end
  end
end
