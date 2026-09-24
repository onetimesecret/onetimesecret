# apps/web/auth/spec/integration/full/omniauth_connect_redirect_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# Issue: #3849 — a completed Connect returns to the panel it started from.
#
# The Connected Identities panel submits the SSO form with connect=1 AND a
# `redirect` field naming itself (/account/settings/security/connections).
# The request phase (hooks/omniauth.rb capture_connect_intent!) stores that
# value in the sso_connect_intent sidecar payload ONLY when it passes
# OT::Utils.safe_internal_path? — the same validator the create-account path
# applies — and the callback's login_redirect override answers with it after
# bind_omniauth_connect_identity succeeds. Everything else keeps Rodauth's
# default post-login redirect, and refusals keep their sign-in error redirect.
#
# WHAT IT LOCKS IN:
#   a. platform Connect + internal redirect  -> callback 302 to that path
#   b. tenant Connect + panel path           -> callback 302 to the panel on
#                                               the tenant host (path-only
#                                               Location, so host is implied)
#   c. external / protocol-relative redirect -> dropped at the request phase;
#                                               callback lands on the default
#                                               login redirect, never off-site
#   d. refused Connect                       -> /signin?auth_error=... wins,
#                                               the panel path is ignored
#   e. absent or invalid redirect param      -> no 'redirect' key in the intent
#
# RUN:
#   tests/lanes/run full-sqlite --only apps/web/auth/spec/integration/full/omniauth_connect_redirect_spec.rb
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../support/oauth_flow_helper'

RSpec.describe 'OmniAuth Connect post-callback return path (#3849)', type: :integration do
  include Rack::Test::Methods

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

  include_context 'domains enabled'

  let(:identities) { auth_db[:account_identities] }
  let(:panel_path) { Auth::Config::Hooks::OmniAuth::CONNECT_PANEL_PATH }

  # Same initiation the panel performs, with the `redirect` field it posts.
  # `redirect: nil` omits the field entirely (the absent case).
  def initiate_sso_connect(redirect:, provider: :oidc, host: nil)
    clear_body_headers
    header 'Host', host if host
    params            = { connect: '1' }
    params[:redirect] = redirect unless redirect.nil?
    post "/auth/sso/#{provider}", params
    last_response.status
  end

  def current_sid
    rack_mock_session.cookie_jar['onetime.session']
  end

  def read_intent(sid)
    Onetime::SessionSidecar.read(sid, 'sso_connect_intent')
  end

  def post_callback(host: nil)
    clear_body_headers
    header 'Host', host if host
    post '/auth/sso/oidc/callback'
    skip 'OmniAuth route not registered (OIDC discovery not available at boot)' if last_response.status == 404
    expect(last_response.status).to eq(302),
      "Expected a post-callback redirect, got #{last_response.status}: #{last_response.body}"
    URI.parse(last_response.location.to_s)
  end

  def expect_bound(uid, account_id)
    rows = identities.where(provider: 'oidc', uid: uid).all
    expect(rows.size).to eq(1), "Expected exactly one bound identity row, got #{rows.inspect}"
    expect(rows.first[:account_id]).to eq(account_id)
  end

  # ==========================================================================
  # a. platform Connect with the panel's internal redirect
  # ==========================================================================

  describe 'platform Connect with an internal redirect' do
    before { enable_platform_fallback }

    it 'returns to the supplied internal path after the bind' do
      email      = unique_test_email('connect-return')
      uid        = "sub-#{SecureRandom.hex(8)}"
      account_id = seed_account_with_password(email)

      csrf_login(email)
      expect(last_response.status).to be_between(200, 302)

      allow(Auth::Logging).to receive(:log_auth_event).and_call_original
      setup_mock_auth(email: email, uid: uid)
      begin
        skip 'OmniAuth route not registered' if initiate_sso_connect(redirect: panel_path) == 404

        sid = current_sid
        expect(read_intent(sid)).to include('redirect' => panel_path)

        landing = post_callback

        expect(landing.host).to be_nil
        expect(landing.path).to eq(panel_path),
          "Expected the callback to return to the panel, got: #{last_response.location.inspect}"
        expect(landing.query.to_s).not_to include('auth_error')
        expect_bound(uid, account_id)
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_identity_connected, hash_including(account_id: account_id))
        expect(Onetime::SessionSidecar.exists?(sid, 'sso_connect_intent')).to be(false)
      ensure
        teardown_mock_auth
      end
    end

    it 'honours any validated internal path, not only the panel' do
      email      = unique_test_email('connect-return-other')
      uid        = "sub-#{SecureRandom.hex(8)}"
      account_id = seed_account_with_password(email)
      target     = '/account/settings/security?tab=identities'

      csrf_login(email)
      setup_mock_auth(email: email, uid: uid)
      begin
        skip 'OmniAuth route not registered' if initiate_sso_connect(redirect: target) == 404

        landing = post_callback

        expect(last_response.location.to_s).to eq(target)
        expect(landing.host).to be_nil
        expect_bound(uid, account_id)
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # b. tenant Connect returns to the panel on the tenant host
  # ==========================================================================

  describe 'tenant Connect with the panel path', :oauth_flow do
    include OAuthFlowHelper

    it 'returns to the panel on the tenant host after the bind' do
      host       = "connect-return-#{SecureRandom.hex(6)}.tenant.example.com"
      email      = unique_test_email('tenant-connect-return')
      uid        = "connect-sub-#{SecureRandom.hex(8)}"
      account_id = seed_account_with_password(email)
      tenant     = setup_oauth_test_domain(host)
      customer   = Onetime::Customer.find_by_extid(auth_db[:accounts].where(id: account_id).get(:external_id))
      Onetime::OrganizationMembership.ensure_membership(
        tenant[:org], customer, role: 'member', domain_scope_id: tenant[:domain].objid, provisioning_source: 'sso'
      )
      Onetime::CustomDomain::SigninConfig.create!(
        domain_id: tenant[:domain].identifier, enabled: true, signin_enabled: true, sso_enabled: true,
      )

      header 'Host', host
      csrf_login(email)
      expect(last_request.env['rack.session']['account_id']).to eq(account_id)

      allow(Auth::Logging).to receive(:log_auth_event).and_call_original
      allow(Onetime.auth_config).to receive(:trust_email_for_linking?).and_return(false)
      setup_mock_auth(email: unique_test_email('asserted-other'), uid: uid)
      begin
        expect(initiate_sso_connect(redirect: panel_path, host: host)).to eq(302)
        sid = last_request.env['rack.session'].id.public_id
        expect(read_intent(sid)).to include(
          'redirect' => panel_path,
          'surface' => { 'kind' => 'custom', 'id' => tenant[:domain].identifier },
        )

        landing = post_callback(host: host)

        # A path-only Location keeps the browser on the tenant host it is on.
        expect(landing.host).to be_nil
        expect(landing.path).to eq(panel_path),
          "Expected the tenant callback to return to the panel, got: #{last_response.location.inspect}"
        expect(landing.query.to_s).not_to include('auth_error')
        expect_bound(uid, account_id)
        expect(last_request.env['rack.session']['account_id']).to eq(account_id)
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_identity_connected, hash_including(account_id: account_id))
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # c. external / protocol-relative redirects are dropped
  # ==========================================================================

  describe 'external redirect targets' do
    before { enable_platform_fallback }

    ['https://evil.example/x', '//evil.example', '/\\evil.example', '/%2F/evil.example'].each do |target|
      it "drops #{target.inspect} and lands on the default login redirect" do
        email      = unique_test_email('connect-evil')
        uid        = "sub-#{SecureRandom.hex(8)}"
        account_id = seed_account_with_password(email)

        csrf_login(email)
        setup_mock_auth(email: email, uid: uid)
        begin
          skip 'OmniAuth route not registered' if initiate_sso_connect(redirect: target) == 404

          sid    = current_sid
          intent = read_intent(sid)
          expect(intent).to include('account_id' => account_id)
          expect(intent).not_to have_key('redirect')

          landing = post_callback

          expect(last_response.location.to_s).not_to include('evil.example')
          expect(landing.host).to be_nil
          expect(landing.path).to eq('/'),
            "Expected Rodauth's default login redirect, got: #{last_response.location.inspect}"
          # The bind itself is unaffected by a rejected return path.
          expect_bound(uid, account_id)
        ensure
          teardown_mock_auth
        end
      end
    end
  end

  # ==========================================================================
  # d. a refused Connect ignores the redirect
  # ==========================================================================

  describe 'refused Connect' do
    before { enable_platform_fallback }

    it 'keeps the sign-in error redirect and never returns to the panel' do
      email      = unique_test_email('connect-refused')
      uid        = "sub-#{SecureRandom.hex(8)}"
      account_id = seed_account_with_password(email)

      csrf_login(email)
      setup_mock_auth(email: email, uid: uid)
      begin
        skip 'OmniAuth route not registered' if initiate_sso_connect(redirect: panel_path) == 404

        sid = current_sid
        expect(read_intent(sid)).to include('redirect' => panel_path)

        # Trip the principal gate after the intent (with its redirect) exists.
        # A missing Customer, not a suspended one: the auth router destroys a
        # suspended session before the Connect hook runs, so that state never
        # reaches the hook-level refusal this example is about.
        auth_db[:accounts].where(id: account_id).update(external_id: "ur#{SecureRandom.hex(8)}")

        allow(Auth::Logging).to receive(:log_auth_event).and_call_original
        clear_body_headers
        post '/auth/sso/oidc/callback'
        skip 'OmniAuth route not registered' if last_response.status == 404

        expect_auth_error_redirect('identity_connect_conflict')
        expect(last_response.location.to_s).not_to include(panel_path)
        expect(identities.where(provider: 'oidc', uid: uid).count).to eq(0)
        expect(Onetime::SessionSidecar.exists?(sid, 'sso_connect_intent')).to be(false)
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_identity_connect_refused, hash_including(reason: 'session_customer_missing'))
        expect(Auth::Logging).not_to have_received(:log_auth_event)
          .with(:omniauth_identity_connected, anything)
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # e. intent payload carries no 'redirect' key for absent or invalid params
  # ==========================================================================

  describe 'intent payload' do
    before { enable_platform_fallback }

    {
      'absent' => nil,
      'blank' => '',
      'relative (no leading slash)' => 'account/settings',
      'absolute URL' => 'https://evil.example/x',
      'protocol-relative' => '//evil.example',
      'backslash' => '/\\evil.example',
      'traversal' => '/account/../evil',
      'array-shaped' => ['/account'],
    }.each do |label, value|
      it "omits the redirect key when the param is #{label}" do
        email = unique_test_email('connect-intent')
        seed_account_with_password(email)

        csrf_login(email)
        setup_mock_auth(email: email)
        begin
          skip 'OmniAuth route not registered' if initiate_sso_connect(redirect: value) == 404

          sid    = current_sid
          intent = read_intent(sid)
          expect(intent).to be_a(Hash)
          expect(intent.keys).to contain_exactly('account_id', 'surface', 'at')
        ensure
          Onetime::SessionSidecar.delete(sid, 'sso_connect_intent') if sid
          teardown_mock_auth
        end
      end
    end

    it 'carries the redirect key only for a validated internal path' do
      email = unique_test_email('connect-intent-ok')
      seed_account_with_password(email)

      csrf_login(email)
      setup_mock_auth(email: email)
      begin
        skip 'OmniAuth route not registered' if initiate_sso_connect(redirect: panel_path) == 404

        sid    = current_sid
        intent = read_intent(sid)
        expect(intent.keys).to contain_exactly('account_id', 'surface', 'at', 'redirect')
        expect(intent['redirect']).to eq(panel_path)
      ensure
        Onetime::SessionSidecar.delete(sid, 'sso_connect_intent') if sid
        teardown_mock_auth
      end
    end
  end
end
