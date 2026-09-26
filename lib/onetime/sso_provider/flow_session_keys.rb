# lib/onetime/sso_provider/flow_session_keys.rb
#
# frozen_string_literal: true

module Onetime
  module SsoProvider
    # The Rack-session keys an OmniAuth strategy parks in its request phase
    # and consumes in its callback. They are the per-flow BINDING between the
    # two phases: an OAuth/OIDC callback must present the parked state (and
    # nonce / PKCE verifier), a SAML response must name the parked
    # AuthnRequest id in InResponseTo. Held in one place because three
    # callers must agree on the list:
    #
    #   - OmniAuth::Strategies::RequestBoundSAML owns SAML_REQUEST_ID
    #     (its REQUEST_ID_KEY);
    #   - Auth::Router logs which of these a session is still carrying when
    #     the active-session gate destroys it mid-flow;
    #   - Auth::Config::Hooks::OmniAuthTenant deletes ALL of them when a new
    #     platform request supersedes an abandoned tenant request, so the
    #     abandoned IdP tab can never complete against the wrong context.
    #
    # All keys are STRINGS: the session is a string-keyed store at rest, and
    # omniauth / omniauth-oauth2 / omniauth_openid_connect write them as
    # string literals. (Rack::Session::Abstract::SessionHash stringifies on
    # access, so a symbol would hit the same slot at runtime, but a plain
    # Hash standing in for the session — as in unit specs — would not.)
    module FlowSessionKeys
      # omniauth (omniauth.params), omniauth-oauth2 (omniauth.state,
      # omniauth.pkce.verifier), omniauth_openid_connect (omniauth.state,
      # omniauth.nonce).
      OMNIAUTH = ['omniauth.state', 'omniauth.nonce', 'omniauth.pkce.verifier', 'omniauth.params'].freeze

      # The one pending SAML AuthnRequest id per session.
      SAML_REQUEST_ID = 'saml_authn_request_id'

      ALL = (OMNIAUTH + [SAML_REQUEST_ID]).freeze
    end
  end
end
