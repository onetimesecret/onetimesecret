# apps/web/auth/spec/integration/full/omniauth_missing_email_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration  (regression for issue #3478)
# =============================================================================
#
# WHAT THIS REPRODUCES:
#   "Unable to login with SSO/EntraID when the user doesn't have an email
#   address" — https://github.com/onetimesecret/onetimesecret/issues/3478
#
#   When the IdP returns no usable email, the OmniAuth callback must fail
#   *closed and loudly*: a 302 redirect to /signin?auth_error=invalid_email
#   (which Login.vue renders as a localized message). It must NOT raise, 500,
#   or leave the browser on a spinner — the reported "frozen loading screen".
#
# PRODUCTION SSO SETUP THAT TRIGGERS THIS (for reference):
#   - Microsoft Entra ID via the v2.0 endpoint (omniauth-entra-id).
#   - A user with NO `mail` attribute (no mailbox/license) -> no `email` claim.
#   - App registration with NO `email` and NO `upn` optional claims. v2.0 omits
#     `upn` by default and emits `preferred_username`, which omniauth-entra-id
#     does NOT use for `info.email`. Net result: OmniAuth `info.email` == nil.
#   - ALLOWED_SIGNUP_DOMAIN unset (otherwise the flow stops at domain_not_allowed
#     before ever reaching the missing-email branch).
#
# HOOK UNDER TEST (provider-agnostic — reads omniauth_email regardless of IdP):
#   apps/web/auth/config/hooks/omniauth.rb:133-150 (before_omniauth_create_account)
#   apps/web/auth/config/hooks/omniauth.rb:27-30   (account_from_omniauth)
#
# WHY WE DRIVE THE :oidc ROUTE:
#   The email guard is provider-agnostic, and the :oidc route is reliably
#   registered at boot (placeholder discovery is stubbed in spec_helper). The
#   mock hashes below are shaped like a real Entra v2.0 id_token so the intent
#   stays faithful to #3478. A best-effort :entra-route variant is included and
#   self-skips when that route isn't registered in this boot.
#
# REQUIREMENTS:
#   - Valkey running on port 2121: pnpm run test:database:start
#   - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
#   - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec \
#     apps/web/auth/spec/integration/full/omniauth_missing_email_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'

RSpec.describe 'OmniAuth Missing Email (issue #3478)', type: :integration do
  include Rack::Test::Methods

  def app
    Onetime::Application::Registry.generate_rack_url_map
  end

  before(:all) do
    # Boot the full Onetime application for integration tests. Mirrors the
    # sibling omniauth_domain_restriction_spec.rb boot — see its comments for
    # why each step is required (force reboot, registry reset, mount assertion).
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

  before(:each) do
    # Tests run on example.org (Rack::Test default), which isn't the canonical
    # domain, so without platform fallback the tenant hook blocks every request
    # before the email guard can run.
    enable_platform_fallback

    # Isolate the missing-email branch: with no signup-domain allowlist the only
    # thing that can reject these logins is the email guard itself.
    configure_allowed_domains(nil)
  end

  # ==========================================================================
  # Helpers
  # ==========================================================================

  # Asserts the OmniAuth callback ended in a 302 redirect to /signin with the
  # given stable auth_error code. The 302 (vs 500/timeout) is itself the
  # regression guard against the "frozen loading screen" symptom.
  def expect_auth_error_redirect(code)
    expect(last_response.status).to eq(302),
      "Expected 302 redirect for #{code}, got #{last_response.status}: #{last_response.body}"
    expect(last_response.location.to_s).to include("/signin?auth_error=#{code}"),
      "Expected auth_error=#{code} in Location, got: #{last_response.location.inspect}"
  end

  # Builds an OmniAuth mock shaped like a Microsoft Entra ID v2.0 id_token.
  #
  # `email:` is what the IdP surfaced as info.email (the only thing the hook
  # reads). Pass nil/''/whitespace to reproduce #3478. `raw_info:` lets a test
  # add claims that ARE present on a v2.0 token (preferred_username, oid, upn)
  # to prove they are not currently used as an email fallback.
  def setup_entra_mock_auth(email:, provider: :oidc, uid: nil, raw_info: {})
    OmniAuth.config.test_mode = true
    OmniAuth.config.allowed_request_methods = %i[get post]

    oid = uid || "oid-#{SecureRandom.uuid}"

    base_raw_info = {
      sub: oid,
      oid: oid,
      tid: 'fabrikam-tenant-id',
      name: 'No Mailbox User',
      preferred_username: 'no.mailbox@fabrikam.onmicrosoft.com',
    }.merge(raw_info)

    OmniAuth.config.mock_auth[provider] = OmniAuth::AuthHash.new({
      provider: provider.to_s,
      uid: oid,
      info: {
        email: email, # nil / '' / whitespace for the #3478 cases
        name: 'No Mailbox User',
      },
      credentials: {
        token: 'mock_access_token',
        expires: false,
      },
      extra: {
        raw_info: base_raw_info,
      },
    })
  end

  def teardown_mock_auth
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.clear
  end

  # Posts the SSO callback, self-skipping if the route isn't registered in this
  # boot (e.g. the :entra route when Entra credentials/orgs_sso aren't present).
  def post_sso_callback(provider = :oidc)
    post "/auth/sso/#{provider}/callback"
    return unless last_response.status == 404

    skip "OmniAuth route /auth/sso/#{provider}/callback not registered in this boot"
  end

  def enable_platform_fallback
    allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
  end

  def configure_allowed_domains(domains)
    config = Marshal.load(Marshal.dump(OT.conf))
    config['site'] ||= {}
    config['site']['authentication'] ||= {}
    config['site']['authentication']['allowed_signup_domains'] = domains
    allow(OT).to receive(:conf).and_return(config)
  end

  # ==========================================================================
  # Core regression: absent / empty email claim  (the #3478 condition)
  # ==========================================================================

  describe 'when the IdP returns no usable email' do
    it 'redirects to invalid_email when the email claim is absent (nil) — the #3478 case' do
      setup_entra_mock_auth(email: nil)

      begin
        post_sso_callback(:oidc)
        # 302 (not 500/hang) is the contract; the stable code lets Login.vue
        # show a localized message instead of freezing on a spinner.
        expect_auth_error_redirect('invalid_email')
      ensure
        teardown_mock_auth
      end
    end

    it 'redirects to invalid_email for an empty-string email' do
      setup_entra_mock_auth(email: '')

      begin
        post_sso_callback(:oidc)
        expect_auth_error_redirect('invalid_email')
      ensure
        teardown_mock_auth
      end
    end

    it 'does not raise when normalizing a nil email in account_from_omniauth' do
      # Guards the account_from_omniauth path (omniauth.rb:27-30):
      # OT::Utils.normalize_email(nil) must coerce to '' rather than blow up,
      # otherwise the callback 500s before reaching the invalid_email redirect.
      setup_entra_mock_auth(email: nil)

      begin
        post_sso_callback(:oidc)
        expect(last_response.status).not_to eq(500),
          "Callback 500'd on nil email instead of redirecting: #{last_response.body}"
        expect_auth_error_redirect('invalid_email')
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # Edge cases: whitespace-only and structurally-malformed emails
  # ==========================================================================

  describe 'whitespace-only email values' do
    [
      ['spaces only',          '   '],
      ['tabs and newlines',    "\t\n"],
      ['non-breaking space',   " "],
    ].each do |label, value|
      it "redirects to invalid_email for #{label}" do
        setup_entra_mock_auth(email: value)

        begin
          post_sso_callback(:oidc)
          expect_auth_error_redirect('invalid_email')
        ensure
          teardown_mock_auth
        end
      end
    end
  end

  describe 'structurally malformed emails from the IdP' do
    [
      ['missing @',        'nomailbox.fabrikam.onmicrosoft.com'],
      ['empty local part', '@fabrikam.onmicrosoft.com'],
      ['empty domain',     'nomailbox@'],
      ['bare @',           '@'],
      ['multiple @',       'no@mailbox@fabrikam.onmicrosoft.com'],
    ].each do |label, value|
      it "redirects to invalid_email for #{label} (#{value.inspect})" do
        setup_entra_mock_auth(email: value)

        begin
          post_sso_callback(:oidc)
          expect_auth_error_redirect('invalid_email')
        ensure
          teardown_mock_auth
        end
      end
    end
  end

  # ==========================================================================
  # Contract: only info.email is consulted (not raw_info claims)
  # ==========================================================================

  describe 'email source contract' do
    it 'uses OmniAuth info.email and ignores a raw_info email claim' do
      # info.email is blank but extra.raw_info carries an email. The hook reads
      # omniauth_email (== info.email), so this must STILL be invalid_email.
      setup_entra_mock_auth(email: nil, raw_info: { email: 'shadow@fabrikam.onmicrosoft.com' })

      begin
        post_sso_callback(:oidc)
        expect_auth_error_redirect('invalid_email')
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # Behavioral tripwires: pins CURRENT behavior so the #3478 fix is deliberate
  # ==========================================================================
  #
  # OTS does not (yet) fall back to preferred_username / upn / oid when the
  # email claim is missing. These tests document that. When the fallback fix
  # for #3478 lands, FLIP these expectations (the login should then proceed
  # instead of redirecting to invalid_email).

  describe 'no email fallback today (update when #3478 fix lands)' do
    it 'does NOT fall back to preferred_username' do
      setup_entra_mock_auth(
        email: nil,
        raw_info: { preferred_username: 'no.mailbox@fabrikam.onmicrosoft.com' },
      )

      begin
        post_sso_callback(:oidc)
        expect_auth_error_redirect('invalid_email')
      ensure
        teardown_mock_auth
      end
    end

    it 'does NOT fall back to a upn claim' do
      setup_entra_mock_auth(
        email: nil,
        raw_info: { upn: 'no.mailbox@fabrikam.onmicrosoft.com' },
      )

      begin
        post_sso_callback(:oidc)
        expect_auth_error_redirect('invalid_email')
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # Boundary: email-shaped values that must NOT be flagged as invalid
  # ==========================================================================

  describe 'email-shaped values are accepted (not flagged invalid)' do
    it 'does not flag an Entra B2B guest UPN that is email-shaped' do
      # Guest UPNs look like `alice_contoso.com#EXT#@fabrikam.onmicrosoft.com`.
      # Ugly, but it has one '@' and a dotted domain, so it passes the malformed
      # guard. It must NOT be rejected as invalid_email (it may proceed to
      # account creation or another step — we only pin that it isn't invalid).
      setup_entra_mock_auth(email: 'alice_contoso.com#EXT#@fabrikam.onmicrosoft.com')

      begin
        post_sso_callback(:oidc)
        expect(last_response.location.to_s).not_to include('auth_error=invalid_email'),
          "Email-shaped guest UPN was wrongly rejected: #{last_response.location.inspect}"
      ensure
        teardown_mock_auth
      end
    end

    it 'does not flag a valid email surrounded by whitespace (normalized away)' do
      setup_entra_mock_auth(email: '  alice@contoso.com  ')

      begin
        post_sso_callback(:oidc)
        expect(last_response.location.to_s).not_to include('auth_error=invalid_email'),
          "Whitespace-padded valid email was wrongly rejected: #{last_response.location.inspect}"
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # Production route: drive the real :entra callback when it is registered
  # ==========================================================================
  #
  # In production the failure surfaces on /auth/sso/entra/callback. This variant
  # exercises that exact route name; it self-skips (via post_sso_callback) when
  # the Entra provider isn't registered in the test boot.

  describe 'via the Entra provider route (when registered)' do
    it 'redirects to invalid_email for a no-mailbox Entra user' do
      setup_entra_mock_auth(email: nil, provider: :entra)

      begin
        post_sso_callback(:entra)
        expect_auth_error_redirect('invalid_email')
      ensure
        teardown_mock_auth
      end
    end
  end
end
