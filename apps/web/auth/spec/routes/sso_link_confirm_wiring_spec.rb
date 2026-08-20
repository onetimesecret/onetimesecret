# apps/web/auth/spec/routes/sso_link_confirm_wiring_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Route module (non-integration)
# =============================================================================
#
# POST /auth/sso-link-confirm — feature-flag wiring into ConfirmSsoLink.
#
# WHAT IT LOCKS IN: the route hands Auth::Operations::ConfirmSsoLink BOTH
# per-feature flags, each read from its own Rodauth route predicate —
#   mfa_feature_loaded:      rodauth.respond_to?(:otp_auth_route)
#   webauthn_feature_loaded: rodauth.respond_to?(:webauthn_auth_route)
# — so the op's second_factor_pending? sees webauthn credentials exactly when
# the webauthn feature is loaded. A dropped/false webauthn flag would let a
# webauthn-only passwordless account be predicted no-MFA and DIRECT-bound
# while its second factor is pending (the MFA-bypassing path #3858 closed for
# OTP). The op's own decision table lives in spec/unit/auth/
# confirm_sso_link_spec.rb; THIS file pins only the route -> op hand-off.
#
# The op is stubbed (captures kwargs, returns :link_expired) and the Redis
# rate limiter is neutralized, so the mini app exercises just the route layer.
# The full mailbox-proof flow stays in
# spec/integration/full/sso_link_confirm_mailbox_proof_spec.rb.
# =============================================================================

require_relative '../spec_helper'
require_relative '../support/route_test_app_helper'
require_relative '../../routes/sso_link_confirm'

RSpec.describe 'POST /sso-link-confirm feature-flag wiring (Auth::Routes::SsoLinkConfirm)' do
  include Rack::Test::Methods
  include RouteTestAppHelper

  let(:db) { create_test_database }
  let(:captured) { {} }

  def build_confirm_app(features)
    app = build_route_test_app(
      db: db,
      route_module: Auth::Routes::SsoLinkConfirm,
      handler: :handle_sso_link_confirm_routes,
      features: features,
    )
    # The canonical LoginRateLimiter needs Redis; the throttle is not under
    # test here, so neutralize its methods (defined on the class, shadowing
    # the included module's).
    app.class_eval do
      def check_login_rate_limit!(*); end
      def record_failed_login_attempt!(*); end
      def clear_login_rate_limit!(*); end
    end
    app
  end

  before do
    # Structured logging goes through global logger state this lane does not
    # boot; logging is not under test.
    allow(Auth::Logging).to receive(:log_auth_event)

    allow(Auth::Operations::ConfirmSsoLink).to receive(:call) do |**kwargs|
      captured.merge!(kwargs)
      # :link_expired ends the route at the 401 branch — no rodauth.login, no
      # SsoLinkVerification, no Familia.
      Auth::Operations::ConfirmSsoLink::Result.new(
        status: :link_expired,
        bound: false,
        second_factor_pending: false,
      )
    end
  end

  def post_confirm
    post '/sso-link-confirm', token: 'tok-under-test'
    expect(last_response.status).to eq(401)
    expect(json_body['error_code']).to eq('link_expired')
  end

  context 'with no second-factor feature loaded (default deploy)' do
    let(:app) { build_confirm_app([:base, :login, :logout]) }

    it 'passes both feature flags as false' do
      post_confirm

      expect(captured[:mfa_feature_loaded]).to be(false)
      expect(captured[:webauthn_feature_loaded]).to be(false)
      expect(captured[:token]).to eq('tok-under-test')
      expect(captured[:db]).to eq(db)
    end
  end

  context 'with only the webauthn feature loaded' do
    let(:app) { build_confirm_app([:base, :login, :logout, :webauthn]) }

    it 'passes webauthn_feature_loaded true and mfa_feature_loaded false' do
      post_confirm

      expect(captured[:mfa_feature_loaded]).to be(false)
      expect(captured[:webauthn_feature_loaded]).to be(true)
    end
  end

  context 'with OTP, recovery, and webauthn features loaded' do
    let(:app) { build_confirm_app([:base, :login, :logout, :otp, :recovery_codes, :webauthn]) }

    it 'passes both feature flags as true' do
      post_confirm

      expect(captured[:mfa_feature_loaded]).to be(true)
      expect(captured[:webauthn_feature_loaded]).to be(true)
    end
  end
end
