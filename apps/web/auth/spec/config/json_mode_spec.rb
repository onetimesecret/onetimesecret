# apps/web/auth/spec/config/json_mode_spec.rb
#
# frozen_string_literal: true

# Spec lives under spec/config/ alongside other config specs even though
# the constant is Auth::JsonMode (not Auth::Config::JsonMode); the file is
# the canonical owner of json-mode wiring, hence the path.
# Plain doubles are used deliberately — we don't load Rodauth::Auth or
# Rack::Request so verifying doubles would fail.
# rubocop:disable RSpec/SpecFilePathFormat, RSpec/VerifiedDoubles

require 'rspec'

# Loads Auth::JsonMode without booting the rest of the auth stack.
# JsonMode is the single owner of rodauth's `only_json?` setter. This spec
# locks in the consolidation behavior so a future per-hook block can't silently
# clobber the SSO or OAuth exemption (Critical-1 from the #3104 review).
#
# Isolation policy: this file MUST NOT load spec_helper (which boots the auth
# application). Booting via this spec would lock the OAuth feature off for
# integration specs whose env-var preamble runs AFTER us in a sorted/random
# order, e.g. oauth_idp_protocol_spec.rb.
#
# An earlier version of this file set `Auth::Application` and `Auth::Config`
# as modules via `module ... end` at the top level. Those assignments
# permanently rebound the constants in the running Ruby process; subsequent
# specs that loaded the real `class Auth::Application` / `class Auth::Config <
# Rodauth::Auth` blew up with `TypeError: X is not a class/module`. Use
# `stub_const` instead — it scopes the rebinding to the example and restores
# (or removes) the constant on teardown, so this spec leaves the namespace
# pristine in any order.

# Source of truth for the exempt list. Kept in sync with apps/web/auth/config/
# hooks/oauth.rb — a divergence here would silently weaken the SSO/OAuth
# exemption coverage. The real constant is stubbed into the live namespace at
# example-time via stub_const so json_mode.rb's `defined?` guard sees it.
OAUTH_EXEMPT_PATHS_FIXTURE = %w[
  /.well-known/openid-configuration
  /.well-known/oauth-authorization-server
  /jwks
  /authorize
  /token
  /userinfo
  /revoke
].freeze

require_relative '../../config/json_mode'

RSpec.describe Auth::JsonMode do
  # Stub the production constants per-example. RSpec restores them after each
  # `it` block, so other specs (and other examples in this file) see whichever
  # binding existed before — class, module, or nothing — and the namespace
  # never gets permanently rebound to the wrong kind.
  before do
    application_stub = Module.new do
      def self.uri_prefix
        '/auth'
      end
    end
    stub_const('Auth::Application', application_stub)
    stub_const('Auth::Config::Hooks::OAuth::OAUTH_EXEMPT_PATHS', OAUTH_EXEMPT_PATHS_FIXTURE)
  end

  def stub_rodauth(path:, omniauth_prefix: nil)
    request = double('Rack::Request', path: path)
    rodauth = double('Rodauth::Auth')
    allow(rodauth).to receive(:request).and_return(request)
    if omniauth_prefix
      allow(rodauth).to receive(:respond_to?).with(:omniauth_prefix).and_return(true)
      allow(rodauth).to receive(:omniauth_prefix).and_return(omniauth_prefix)
    else
      allow(rodauth).to receive(:respond_to?).with(:omniauth_prefix).and_return(false)
    end
    rodauth
  end

  describe '.exempt?' do
    context 'with OAuth/OIDC endpoint paths' do
      OAUTH_EXEMPT_PATHS_FIXTURE.each do |suffix|
        it "exempts /auth#{suffix}" do
          rodauth = stub_rodauth(path: "/auth#{suffix}")
          expect(described_class.exempt?(rodauth)).to be true
        end
      end

      it 'exempts a subpath under /token (e.g., future /token/info)' do
        rodauth = stub_rodauth(path: '/auth/token/info')
        expect(described_class.exempt?(rodauth)).to be true
      end
    end

    context 'when omniauth feature is loaded (SSO paths)' do
      it 'exempts the prefix root /auth/sso' do
        rodauth = stub_rodauth(path: '/auth/sso', omniauth_prefix: '/sso')
        expect(described_class.exempt?(rodauth)).to be true
      end

      it 'exempts /auth/sso/oidc/callback' do
        rodauth = stub_rodauth(path: '/auth/sso/oidc/callback', omniauth_prefix: '/sso')
        expect(described_class.exempt?(rodauth)).to be true
      end
    end

    context 'when both OAuth and SSO exemption sources are active' do
      it 'exempts OAuth paths' do
        rodauth = stub_rodauth(path: '/auth/authorize', omniauth_prefix: '/sso')
        expect(described_class.exempt?(rodauth)).to be true
      end

      it 'exempts SSO paths' do
        rodauth = stub_rodauth(path: '/auth/sso/oidc', omniauth_prefix: '/sso')
        expect(described_class.exempt?(rodauth)).to be true
      end

      it 'does NOT exempt non-OAuth, non-SSO paths' do
        rodauth = stub_rodauth(path: '/auth/login', omniauth_prefix: '/sso')
        expect(described_class.exempt?(rodauth)).to be false
      end
    end

    context 'with edge-case paths' do
      it 'does not match /auth/sso-admin (no trailing-slash boundary)' do
        rodauth = stub_rodauth(path: '/auth/sso-admin', omniauth_prefix: '/sso')
        expect(described_class.exempt?(rodauth)).to be false
      end

      it 'does not match /auth/tokens-list (no trailing-slash boundary)' do
        rodauth = stub_rodauth(path: '/auth/tokens-list', omniauth_prefix: '/sso')
        expect(described_class.exempt?(rodauth)).to be false
      end

      it 'returns false for an arbitrary unrelated path' do
        rodauth = stub_rodauth(path: '/auth/profile')
        expect(described_class.exempt?(rodauth)).to be false
      end
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat, RSpec/VerifiedDoubles
