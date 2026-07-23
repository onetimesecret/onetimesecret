# apps/web/auth/spec/integration/full/omniauth_trusted_link_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# Issue: #3836 / #3840 Phase 1 — opt-in, per-provider, boot-guarded
#        "trusted IdP email-linking" escape hatch.
#
# WHY THIS FILE EXISTS (PR #3844 review gap #2729 / S4):
#   The decision-boundary examples in
#   apps/web/auth/spec/config/hooks/omniauth_spec.rb are a REIMPLEMENTATION of
#   the gate order in _account_from_omniauth — they do NOT drive the production
#   hook, so a refactor of hooks/omniauth.rb could silently break the trusted
#   auto-link path without failing a test. This file closes that gap by driving
#   the REAL Rodauth omniauth callback through the Rack stack and asserting the
#   persisted side effects (the account_identities row, the redirect, the audit
#   event) that only the production machinery produces.
#
# WHAT IT LOCKS IN (production code: apps/web/auth/config/hooks/omniauth.rb):
#   1. PLATFORM path + trust flag ON + existing account located by email
#        -> account_from_omniauth returns the existing account, rodauth-omniauth
#           persists the (provider, uid) account_identities row bound to that
#           account (the auto-link), and the :omniauth_email_linked_trusted_provider
#           warn audit event fires. No refusal redirect.
#   2. PLATFORM path + trust flag OFF (H-3 refusal, unchanged)
#        -> redirect to /signin?auth_error=account_exists_link_required, NO
#           identity row created, :omniauth_link_refused_existing_account fires.
#   3. TENANT path (session[:validated_omniauth_domain_id] present) + trust ON
#        -> STILL refuses; the trust flag must never affect the multi-tenant
#           surface. Redirect to account_exists_link_required, no row created.
#
# HOW IT DIFFERS FROM omniauth_spec.rb: that file asserts the *decision* in
# isolation (pure logic); this file asserts the *effects* end-to-end through
# the gem's _handle_omniauth_callback. Both are kept — the unit boundary is
# fast and exhaustive on casing/edge inputs; this integration layer is the
# regression guard for the wiring.
#
# HARNESS NOTES:
#   - trust_email_for_linking?(provider) is stubbed per-example (the flag itself
#     is owned/tested elsewhere — auth_config.rb + omniauth_spec boundary). This
#     spec is about the HOOK's behavior GIVEN the flag, not the flag's plumbing.
#   - An existing account is seeded directly into the accounts table with
#     status_id = STATUS_VERIFIED (2) so _account_from_login locates it (the
#     lookup filters status IN (unverified, verified) when verify_account is on)
#     and open_account? short-circuits the gem's verify branch. A linked Customer
#     is created so after_login's SyncSession resolves cleanly.
#   - Platform path: POST the callback directly with enable_platform_fallback
#     (validated_omniauth_domain_id stays nil). Tenant path: initiate + callback
#     from a registered custom-domain host (OAuthFlowHelper) so the tenant hook
#     sets validated_omniauth_domain_id before account_from_omniauth runs.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTHENTICATION_MODE=full, AUTH_DATABASE_URL (SQLite in-memory; rake sets it)
#
# RUN:
#   bundle exec rake spec:integration:full \
#     SPEC=apps/web/auth/spec/integration/full/omniauth_trusted_link_spec.rb
#
#   # Standalone (rake supplies these; set them yourself for a bare rspec run):
#   RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL=sqlite::memory: \
#     ORGS_SSO_ENABLED=true LANG=en_US.UTF-8 \
#     bundle exec rspec apps/web/auth/spec/integration/full/omniauth_trusted_link_spec.rb \
#     --tag '~postgres_database'
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../support/oauth_flow_helper'

RSpec.describe 'OmniAuth trusted-provider email linking (#3836 Phase 1)', type: :integration do
  include Rack::Test::Methods

  def app
    Onetime::Application::Registry.generate_rack_url_map
  end

  before(:all) do
    # Mirror the proven boot in omniauth_domain_restriction_spec.rb: force a
    # clean reboot so provider registration runs against this suite's WebMock
    # stubs + ENV, and assert the auth app actually mounted (a silent empty
    # registry would turn every callback into a 404 → skip).
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

  # Enables platform credential fallback for non-tenant requests. Tests run on
  # example.org (Rack::Test default), which isn't the canonical domain, so
  # without this the tenant hook blocks the callback before account lookup.
  # Leaves session[:validated_omniauth_domain_id] nil == the PLATFORM path.
  def enable_platform_fallback
    allow(Onetime.auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
  end

  # Force the trust flag decision for a given route without touching the
  # auth_config plumbing (owned by another agent / tested separately). Any other
  # provider falls through to the real implementation.
  def stub_trust_for(route, enabled)
    allow(Onetime.auth_config).to receive(:trust_email_for_linking?).and_call_original
    allow(Onetime.auth_config).to receive(:trust_email_for_linking?)
      .with(route).and_return(enabled)
  end

  # Seed a pre-existing VERIFIED account (accounts row + linked Customer) that
  # _account_from_login will locate by normalized email. status_id = 2 (Verified)
  # both satisfies the lookup's status filter AND makes open_account? true so the
  # gem skips its verify-account branch. Returns the account_id.
  def seed_existing_account(email)
    normalized = OT::Utils.normalize_email(email)
    customer   = Onetime::Customer.new(email: normalized)
    customer.save
    auth_db[:accounts].insert(
      email: normalized,
      status_id: AuthTestConstants::STATUS_VERIFIED,
      external_id: customer.extid,
    )
  end

  # OmniAuth test-mode mock for a successful IdP assertion of `email`/`uid`.
  def setup_mock_auth(email:, uid:, provider: :oidc)
    OmniAuth.config.test_mode = true
    OmniAuth.config.allowed_request_methods = %i[get post]
    OmniAuth.config.mock_auth[provider] = OmniAuth::AuthHash.new({
      provider: provider.to_s,
      uid: uid,
      info: { email: email, name: 'Trusted Link User', email_verified: true },
      credentials: {
        token: 'mock_access_token',
        expires_at: Time.now.to_i + 3600,
        expires: true,
      },
      extra: {
        raw_info: { sub: uid, email: email, name: 'Trusted Link User', email_verified: true },
      },
    })
  end

  def teardown_mock_auth
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.clear
  end

  # ==========================================================================
  # Scenario 1 — PLATFORM path + trust flag ON -> auto-link
  # ==========================================================================

  describe 'platform path, trust flag ON' do
    before { enable_platform_fallback }

    it 'links the IdP identity to the existing account and fires the trusted warn event' do
      email = "trusted-#{SecureRandom.hex(6)}@company.example.com"
      uid   = "sub-#{SecureRandom.hex(8)}"
      account_id = seed_existing_account(email)

      stub_trust_for('oidc', true)
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original

      setup_mock_auth(email: email, uid: uid)
      begin
        post '/auth/sso/oidc/callback'

        if last_response.status == 404
          skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
        end

        # It must NOT have taken the H-3 refusal path.
        expect(last_response.location.to_s).not_to include('account_exists_link_required'),
          "Trusted platform link should auto-link, not refuse. Location: #{last_response.location.inspect}"
        expect(last_response.status).to eq(302),
          "Expected a post-login redirect, got #{last_response.status}: #{last_response.body}"

        # The auto-link: exactly one (provider, uid) identity row, bound to the
        # pre-existing account. This row is created ONLY by the gem's
        # create_omniauth_identity, which runs ONLY because the production hook
        # returned the located account (`next existing`).
        rows = identities.where(provider: 'oidc', uid: uid).all
        expect(rows.size).to eq(1),
          "Expected exactly one linked identity row, got #{rows.size}: #{rows.inspect}"
        expect(rows.first[:account_id]).to eq(account_id),
          'Linked identity must bind to the pre-existing account (the auto-link)'

        # The distinctive warn audit event for the trusted-link branch.
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_email_linked_trusted_provider, hash_including(provider: 'oidc'))
        # And it must NOT have logged the refusal event.
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_link_refused_existing_account, anything)
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # Scenario 2 — PLATFORM path + trust flag OFF -> no trusted-provider auto-link
  # ==========================================================================
  #
  # This test's property is the TRUST gate: with trust off, the trusted-provider
  # auto-link branch is skipped and no identity row is created. The post-skip
  # redirect is incidental — a passwordless account now takes the Phase 4 mailbox
  # path (link_verification_sent, asserted in sso_link_confirm_mailbox_proof_spec.rb)
  # rather than the old H-3 refusal — so it is not pinned here.

  describe 'platform path, trust flag OFF' do
    before { enable_platform_fallback }

    it 'refuses to auto-link and creates no identity row when trust is off' do
      email = "refuse-#{SecureRandom.hex(6)}@company.example.com"
      uid   = "sub-#{SecureRandom.hex(8)}"
      seed_existing_account(email)

      stub_trust_for('oidc', false)
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original

      setup_mock_auth(email: email, uid: uid)
      begin
        post '/auth/sso/oidc/callback'

        if last_response.status == 404
          skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
        end

        # A 302 redirect is issued; its target is incidental to the TRUST property
        # (a passwordless account now takes the Phase 4 mailbox path, asserted in
        # sso_link_confirm_mailbox_proof_spec.rb), so it is not pinned here.
        expect(last_response.status).to eq(302),
          "Expected a 302 redirect, got #{last_response.status}: #{last_response.body}"

        # No auto-link: the (provider, uid) row must not exist. The trusted-link
        # branch is skipped when trust is off, so the caller's IdP identity is never
        # auto-bound to the pre-existing account.
        expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0),
          'Trust OFF must NOT create an account_identities row'

        # And the trusted-provider auto-link event never fires.
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_email_linked_trusted_provider, anything)
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # Scenario 3 — TENANT path + trust flag ON -> STILL refuses
  # ==========================================================================
  #
  # The trust flag is scoped to the PLATFORM (env-configured) surface by
  # construction: the hook requires session[:validated_omniauth_domain_id] to be
  # nil. Here we initiate + call back from a registered custom-domain host so the
  # tenant hook sets that key BEFORE account_from_omniauth runs — the trusted
  # branch's guard fails and H-3 refusal applies even with trust ON. This is the
  # multi-tenant takeover guard: an operator's platform trust declaration must
  # not weaken any tenant's SSO surface.

  describe 'tenant path, trust flag ON (must still refuse)', :oauth_flow do
    include OAuthFlowHelper

    it 'refuses on the multi-tenant surface despite the trust flag' do
      run_id = "trust-tenant-#{SecureRandom.hex(4)}"
      host   = "secrets-#{run_id}.tenant.example.com"
      email  = "tenant-user-#{run_id}@tenant.example.com"
      uid    = "sub-#{SecureRandom.hex(8)}"

      # Registered tenant domain + SsoConfig so the tenant callback validates.
      setup_oauth_test_domain(host)
      # Pre-existing account that the tenant SSO email resolves to.
      seed_existing_account(email)

      # Trust ON platform-wide — it must have NO effect on the tenant surface.
      stub_trust_for('oidc', true)
      allow(Auth::Logging).to receive(:log_auth_event).and_call_original

      OmniAuth.config.test_mode = true
      OmniAuth.config.allowed_request_methods = %i[get post]
      OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new({
        provider: 'oidc',
        uid: uid,
        info: { email: email, name: 'Tenant User', email_verified: true },
        extra: { raw_info: { sub: uid, email: email, email_verified: true } },
      })

      begin
        # Phase 1: initiate from the tenant host so the tenant hook records
        # the domain context in session.
        header 'Host', host
        post '/auth/sso/oidc'

        if last_response.status == 404
          skip "OmniAuth route not registered for #{host} (OIDC discovery not available at boot)"
        end
        expect(last_response.status).to eq(302),
          "Tenant initiation should redirect, got #{last_response.status}: #{last_response.body}"

        # Phase 2: callback from the SAME host. before_omniauth_callback_route
        # validates and sets :validated_omniauth_domain_id, so the trust branch's
        # `session[:validated_omniauth_domain_id].nil?` guard is false.
        header 'Host', host
        post '/auth/sso/oidc/callback'

        expect(last_response.status).to eq(302),
          "Expected refusal redirect, got #{last_response.status}: #{last_response.body}"
        expect(last_response.location.to_s).to include('/signin?auth_error=account_exists_link_required'),
          "Tenant surface must refuse regardless of trust flag. Location: #{last_response.location.inspect}"

        # No auto-link on the tenant surface.
        expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0),
          'Tenant refusal must NOT create an account_identities row'

        # The refusal event fired; the trusted-link event did NOT.
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_link_refused_existing_account, hash_including(provider: 'oidc'))
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_email_linked_trusted_provider, anything)
      ensure
        teardown_mock_auth
      end
    end
  end
end
