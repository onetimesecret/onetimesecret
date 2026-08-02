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
#   - ORGS_SSO_ENABLED=true so the /auth/sso/* routes register (provided by
#     .env.test). Without it every example self-skips via the 404 guard.
#
# RUN:
#   source .env.test && pnpm run test:rspec \
#     apps/web/auth/spec/integration/full/omniauth_missing_email_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'

RSpec.describe 'OmniAuth Missing Email (issue #3478)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    # Boot the full Onetime application for integration tests. Mirrors the
    # sibling omniauth_domain_restriction_spec.rb boot — see its comments for
    # why each step is required (force reboot, registry reset, mount assertion).
    #
    # NOTE: the SSO callback routes (/auth/sso/oidc, /auth/sso/entra) only
    # register when SSO is enabled, which config.yaml derives from
    # ORGS_SSO_ENABLED. That must be set in the environment BEFORE this process
    # starts (it is provided by .env.test) — setting it here would be too late
    # because the ERB config is evaluated when spec_helper loads. When it is
    # unset the examples self-skip via the 404 guard in post_sso_callback.
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

  # Builds an OmniAuth mock shaped like a Microsoft Entra ID v2.0 id_token.
  #
  # `email:` is what the IdP surfaced as info.email. Pass nil/''/whitespace to
  # reproduce #3478. `raw_info:` lets a test add claims that ARE present on a
  # v2.0 token. Two distinct roles there since the #3499 fix:
  #   - `mail:` is a TIER-1 verified mailbox claim and IS used as a fallback.
  #   - preferred_username / upn / oid are TIER-2 (mutable) and are NOT — the
  #     tripwires below prove the hook still refuses them.
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

  # teardown_mock_auth comes from support/omniauth_test_helper.rb. The SETUP
  # stays local: the shared setup_mock_auth omits an absent email claim, while
  # #3478 needs info.email PRESENT and nil/blank.

  # Posts the SSO callback, self-skipping if the route isn't registered in this
  # boot (e.g. the :entra route when Entra credentials/orgs_sso aren't present).
  def post_sso_callback(provider = :oidc)
    post "/auth/sso/#{provider}/callback"
    return unless last_response.status == 404

    skip "OmniAuth route /auth/sso/#{provider}/callback not registered in this boot"
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
  # Contract: only info.email and raw_info["mail"] are consulted
  # ==========================================================================

  describe 'email source contract' do
    it 'ignores a raw_info email claim (only the "mail" key is a fallback)' do
      # info.email is blank and extra.raw_info carries an "email" key — which is
      # NOT the "mail" mailbox attribute omniauth_email falls back to. No other
      # raw_info claim may be consulted, so this must STILL be invalid_email.
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
  # Tier-1 fallback: extra.raw_info["mail"]  (#3499 Phase 1)
  # ==========================================================================
  #
  # The #3478 fix. An Entra user with no Exchange mailbox — or an app
  # registration missing the email optional claim — arrives with info.email
  # absent but the verified mailbox attribute `mail` present. That user must
  # now sign in instead of hitting invalid_email.

  describe 'verified-mailbox fallback' do
    it 'falls back to extra.raw_info["mail"] when info.email is absent' do
      setup_entra_mock_auth(email: nil, raw_info: { mail: 'has.mailbox@fabrikam.onmicrosoft.com' })

      begin
        post_sso_callback(:oidc)
        expect(last_response.status).to eq(302),
          "Expected a post-login redirect, got #{last_response.status}: #{last_response.body}"
        expect(last_response.location.to_s).not_to include('auth_error='),
          "Expected sign-in to proceed, got: #{last_response.location.inspect}"
      ensure
        teardown_mock_auth
      end
    end

    it 'prefers info.email over raw_info["mail"] when both are present' do
      setup_entra_mock_auth(
        email: 'primary@fabrikam.onmicrosoft.com',
        raw_info: { mail: 'secondary@fabrikam.onmicrosoft.com' },
      )

      begin
        post_sso_callback(:oidc)
        expect(last_response.status).to eq(302)
        expect(last_response.location.to_s).not_to include('auth_error=')
        # info.email is the account that must exist; the mailbox attribute
        # must not have shadowed it.
        expect(Onetime::Customer.email_exists?('primary@fabrikam.onmicrosoft.com')).to be(true)
        expect(Onetime::Customer.email_exists?('secondary@fabrikam.onmicrosoft.com')).to be(false)
      ensure
        teardown_mock_auth
      end
    end

    it 'finds the mail claim whether the strategy keyed raw_info with symbols or strings' do
      # omniauth_email reads raw_info['mail'] with a STRING key. That is safe for
      # symbol-keyed strategies because omniauth_auth is an OmniAuth::AuthHash
      # (Hashie::Mash), which converts nested hashes on assignment and reads
      # indifferently. The sibling examples above cover the symbol-keyed shape
      # (setup_entra_mock_auth builds raw_info with symbol keys); this one pins
      # the string-keyed shape so neither access path can regress unnoticed.
      local = "string.keyed.#{SecureRandom.hex(4)}"
      setup_entra_mock_auth(email: nil, raw_info: { 'mail' => "#{local}@fabrikam.onmicrosoft.com" })

      begin
        post_sso_callback(:oidc)
        expect(last_response.status).to eq(302)
        expect(last_response.location.to_s).not_to include('auth_error='),
          "String-keyed mail claim was not resolved: #{last_response.location.inspect}"
      ensure
        teardown_mock_auth
      end
    end

    it 'still redirects to invalid_email when mail is blank too' do
      setup_entra_mock_auth(email: nil, raw_info: { mail: '   ' })

      begin
        post_sso_callback(:oidc)
        expect_auth_error_redirect('invalid_email')
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # Behavioral tripwires: TIER-2 claims are still refused
  # ==========================================================================
  #
  # The #3499 fallback is deliberately scoped to tier-1 verified mailbox
  # claims. preferred_username / upn / oid are mutable per Microsoft's own
  # guidance, so linking on them is an account-takeover vector. These pin the
  # refusal — they must NOT be flipped alongside the `mail` fallback above.

  describe 'no fallback to mutable tier-2 identifiers' do
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
        # Asserting the STATUS, not just the location string, is load-bearing:
        # a 500 has no Location header, so a location-only assertion passes on
        # the very failure this example exists to catch (it did — see below).
        expect(last_response.status).to eq(302),
          "Whitespace-padded email did not complete the callback (#{last_response.status})"
        expect(last_response.location.to_s).not_to include('auth_error=invalid_email'),
          "Whitespace-padded valid email was wrongly rejected: #{last_response.location.inspect}"
      ensure
        teardown_mock_auth
      end
    end

    it 'creates the account with the whitespace trimmed off' do
      # REGRESSION: omniauth_email is the value Rodauth INSERTS
      # (_omniauth_new_account(omniauth_email) -> omniauth_save_account). It
      # used to return the claim verbatim, so a padded address passed the
      # before_omniauth_create_account guard (which strips its own copy) and
      # then violated the accounts.valid_email CHECK — spaces are excluded from
      # both the local part and the domain — producing a 500 on the callback
      # instead of a sign-in. Pin the trimmed value landing in the account row.
      padded  = "  trimmed.#{SecureRandom.hex(4)}@contoso.com  "
      trimmed = padded.strip
      setup_entra_mock_auth(email: padded)

      begin
        post_sso_callback(:oidc)
        expect(last_response.status).to eq(302),
          "Padded email 500'd instead of signing in: #{last_response.body}"
        expect(last_response.location.to_s).not_to include('auth_error=')
        expect(Onetime::Customer.email_exists?(trimmed)).to be(true),
          "Expected the account to be created under #{trimmed.inspect}"
      ensure
        teardown_mock_auth
      end
    end

    it 'trims whitespace on the raw_info["mail"] fallback too' do
      # Same insert path, reached via the #3499 tier-1 fallback rather than
      # info.email — the trim must apply to both claim sources.
      local = "padded.mail.#{SecureRandom.hex(4)}"
      setup_entra_mock_auth(email: nil, raw_info: { mail: "  #{local}@contoso.com\n" })

      begin
        post_sso_callback(:oidc)
        expect(last_response.status).to eq(302),
          "Padded mail fallback 500'd instead of signing in: #{last_response.body}"
        expect(last_response.location.to_s).not_to include('auth_error=')
        expect(Onetime::Customer.email_exists?("#{local}@contoso.com")).to be(true)
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
