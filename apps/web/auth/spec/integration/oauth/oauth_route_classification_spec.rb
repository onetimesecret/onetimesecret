# apps/web/auth/spec/integration/oauth/oauth_route_classification_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration
# =============================================================================
#
# Route classification coverage WITH the OAuth IdP feature mounted.
#
# The OAuth feature (config/features/oauth.rb) registers five Rodauth routes
# via auth_server_route — authorize, token, revoke, userinfo, jwks — that land
# in Auth::Config.route_hash only when AUTH_OAUTH_ENABLED=true. The three
# hand-kept classification tables (Auth::SigninGate::UNGATED_ROUTES,
# Auth::RestrictTo::UNGATED_ROUTES, Auth::Router::ANONYMOUS_RODAUTH_ROUTES)
# must know them, and the coverage specs in integration/full/ that enforce
# ADR-038#classify-exhaustively-or-fail never see them because that lane boots
# with the feature off. This file is the same coverage check, run with the
# feature on.
#
# REQUIREMENTS:
# - Valkey on the lane's test port
# - AUTHENTICATION_MODE=full
# - AUTH_OAUTH_ENABLED=true (set below, pre-boot; the lane env does not set it)
# - OAUTH_JWT_RSA_PRIVATE_KEY (generated below if absent)
#
# RUN (full-sqlite lane; see tests/lanes/README.md):
#   tests/lanes/run full-sqlite --only apps/web/auth/spec/integration/oauth/oauth_route_classification_spec.rb
#   tests/lanes/run full-sqlite   # whole lane: spec:integration:full, then spec:integration:oauth
#
# This spec lives at integration/oauth/ (not integration/full/) for the same
# reason its siblings do: the path-keyed MockAuthConfig spec/spec_helper.rb
# installs for /integration/full/ has no oauth_enabled? and would turn the IdP
# feature off at boot, and the oauth specs write AUTH_OAUTH_ENABLED
# process-wide, so they get an isolated invocation (spec:integration:oauth).
# =============================================================================

require 'openssl'
require 'securerandom'

# Pre-boot env: same shape as the sibling oauth specs so all can run in one
# rspec invocation (boot is memoized; first writer wins on AUTH_OAUTH_ENABLED).
ENV['AUTH_OAUTH_ENABLED']           = 'true'
ENV['OAUTH_ISSUER']               ||= 'http://localhost:3000/auth'
ENV['OAUTH_JWT_RSA_PRIVATE_KEY']  ||= OpenSSL::PKey::RSA.new(2048).to_pem
ENV['OAUTH_SP_DEV_CLIENT_SECRET'] ||= "spec-sp-secret-#{SecureRandom.hex(12)}"

ENV['AUTHENTICATION_MODE'] ||= 'full'
ENV['RACK_ENV']            ||= 'test'

require_relative '../../spec_helper'

RSpec.describe 'Rodauth route classification with the OAuth IdP mounted', :sqlite_database, type: :integration do
  let(:idp_routes)     { [:authorize, :token, :revoke, :userinfo, :jwks] }
  let(:machine_routes) { [:token, :revoke, :userinfo, :jwks] }

  before(:all) do
    boot_onetime_app

    unless Onetime.auth_config.oauth_enabled?
      raise <<~MSG
        OAuth IdP feature is not enabled in the booted Onetime app. Run this
        spec in isolation or before any other integration spec that boots
        without AUTH_OAUTH_ENABLED.
      MSG
    end
  end

  # Rodauth freezes route_hash in post_configure, so this reads the LIVE mounted
  # route set — same derivation as the integration/full/ coverage specs.
  def mounted_route_names
    Auth::Config.route_hash.values.map { |meth| meth.to_s.delete_prefix('handle_').to_sym }
  end

  # What distinguishes this file from its integration/full/ siblings: the five
  # IdP routes are actually mounted, so the coverage checks below are not
  # vacuous with respect to them.
  it 'mounts the five OAuth IdP routes (guards against a vacuous pass)' do
    expect(mounted_route_names).to include(*idp_routes)
    expect(mounted_route_names).to include(:login, :logout)
  end

  describe 'sign-in / sign-up opt-in axis (Auth::SigninGate)' do
    let(:gate) { Auth::SigninGate }

    it 'classifies every mounted Rodauth route as gated or explicitly exempt' do
      classified   = gate::GATED_ROUTES + gate::UNGATED_ROUTES
      unclassified = mounted_route_names - classified

      expect(unclassified).to be_empty,
        "Rodauth routes with no sign-in/sign-up opt-in classification: #{unclassified.inspect}\n" \
        'Add each to SIGNIN_ROUTES / SIGNUP_ROUTES or UNGATED_ROUTES (with a reason) ' \
        'in apps/web/auth/signin_gate.rb. See ADR-024.'
    end

    it 'exempts the IdP routes rather than gating them' do
      expect(gate::UNGATED_ROUTES).to include(*idp_routes)
      expect(gate::GATED_ROUTES & idp_routes).to be_empty
    end
  end

  describe 'restrict_to axis (Auth::RestrictTo)' do
    let(:gate) { Auth::RestrictTo }

    it 'classifies every mounted Rodauth route as gated or explicitly exempt' do
      classified   = gate::GATED_ROUTES.keys + gate::UNGATED_ROUTES
      unclassified = mounted_route_names - classified

      expect(unclassified).to be_empty,
        "Rodauth routes with no restrict_to classification: #{unclassified.inspect}\n" \
        'Add each to GATED_ROUTES (with its sign-in method) or UNGATED_ROUTES (with a reason) ' \
        'in apps/web/auth/restrict_to.rb. See ADR-034.'
    end

    it 'exempts the IdP routes rather than gating them' do
      expect(gate::UNGATED_ROUTES).to include(*idp_routes)
      expect(gate::GATED_ROUTES.keys & idp_routes).to be_empty
    end
  end

  describe 'active-session gate lists (Auth::Router)' do
    # Rodauth feature files whose routes appear in the router's lists but that
    # this lane boots with the feature OFF (the oauth lane sets no MFA,
    # webauthn or email_auth env). Requiring a feature file only registers it
    # in Rodauth::FEATURES with its route list; it does not enable it on
    # Auth::Config. This lets the resolution check below cover names whose
    # `<name>_route` reader is absent in this boot instead of skipping them,
    # which is what the router's respond_to? guard does at runtime.
    let(:registry_route_names) do
      %w[email_auth verify_account otp recovery_codes webauthn webauthn_login webauthn_autofill].each do |feature|
        require "rodauth/features/#{feature}"
      end
      Rodauth::FEATURES.values.flat_map(&:routes).map { |meth| meth.to_s.delete_prefix('handle_').to_sym }.uniq
    end

    let(:router)  { Auth::Router.new(Rack::MockRequest.env_for('/')) }
    let(:rodauth) { router.rodauth }

    # These lists RESOLVE; they are not required to be exhaustive. The
    # anonymous axis fails closed (an unlisted route on a revoked cookie is
    # refused with a 401), so an omission is a usability defect a route-level
    # spec catches, not an access widening. What this catches is a renamed or
    # removed route lingering in a hand-kept list, which the router's
    # respond_to?(:"<name>_route") guard would otherwise skip silently forever.
    #
    # Two halves because the lane mounts only a subset of the app's features:
    # a name with a LIVE reader must be in route_hash (a reader without a
    # handler is the drift the guard cannot see), and every name — reader or
    # not — must be a route some Rodauth feature defines.
    {
      'ANONYMOUS_RODAUTH_ROUTES' => Auth::Router::ANONYMOUS_RODAUTH_ROUTES,
      'MFA_PENDING_RODAUTH_ROUTES' => Auth::Router::MFA_PENDING_RODAUTH_ROUTES,
    }.each do |list_name, names|
      it "#{list_name}: every name with a live route reader is mounted" do
        live  = names.select { |name| rodauth.respond_to?(:"#{name}_route") }
        stale = live - mounted_route_names

        expect(stale).to be_empty,
          "#{list_name} names routes with a `_route` reader but no mounted handler: #{stale.inspect}"
      end

      it "#{list_name}: every name is a route some Rodauth feature defines" do
        unknown = names - registry_route_names

        expect(unknown).to be_empty,
          "#{list_name} names routes no Rodauth feature defines (renamed or removed?): #{unknown.inspect}"
      end
    end

    # token/revoke/userinfo authenticate by client credentials or bearer token
    # and jwks is public key material; none read the Rack session, so a stale
    # cookie must not turn into a 401 on them. authorize is browser-driven and
    # login-required, so it takes the same 401 as every other such route.
    it 'treats the four machine routes as anonymous and authorize as login-required' do
      expect(Auth::Router::ANONYMOUS_RODAUTH_ROUTES).to include(*machine_routes)
      expect(Auth::Router::ANONYMOUS_RODAUTH_ROUTES).not_to include(:authorize)
      expect(Auth::Router::MFA_PENDING_RODAUTH_ROUTES & idp_routes).to be_empty
    end

    it 'answers anonymous_rodauth_route? from the live route paths' do
      machine_routes.each do |name|
        path = "/#{rodauth.public_send(:"#{name}_route")}"
        expect(router.anonymous_rodauth_route?(path)).to be(true), "#{name} (#{path}) should be anonymous"
      end

      authorize_path = "/#{rodauth.authorize_route}"
      expect(router.anonymous_rodauth_route?(authorize_path)).to be(false)
    end
  end
end
