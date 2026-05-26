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

# Minimal stubs so json_mode.rb can be required in isolation. JsonMode lives
# at Auth::JsonMode (not Auth::JsonMode), so we don't need to care
# about whether Auth::Config has been stubbed as a class or module by
# another spec — we only stub what we actually consume.

module Auth
  module Application
    def self.uri_prefix
      '/auth'
    end
  end
end

# Stub the OAUTH_EXEMPT_PATHS constant. We poke it into Auth::Config::Hooks::OAuth
# defensively so this spec works whether Auth::Config has been loaded as a
# class (production) or module (stubbed by another spec) — defined? + const_set
# tolerates both.
Auth.const_set(:Config, Module.new) unless defined?(Auth::Config)
unless Auth::Config.const_defined?(:Hooks)
  Auth::Config.const_set(:Hooks, Module.new)
end
unless Auth::Config::Hooks.const_defined?(:OAuth)
  Auth::Config::Hooks.const_set(:OAuth, Module.new)
end
unless Auth::Config::Hooks::OAuth.const_defined?(:OAUTH_EXEMPT_PATHS)
  Auth::Config::Hooks::OAuth.const_set(
    :OAUTH_EXEMPT_PATHS,
    %w[
      /.well-known/openid-configuration
      /.well-known/oauth-authorization-server
      /jwks
      /authorize
      /token
      /userinfo
      /revoke
    ].freeze,
  )
end

require_relative '../../config/json_mode'

RSpec.describe Auth::JsonMode do
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
      Auth::Config::Hooks::OAuth::OAUTH_EXEMPT_PATHS.each do |suffix|
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
