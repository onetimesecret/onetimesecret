# lib/onetime/sso_provider/apple.rb
#
# frozen_string_literal: true

# Sign in with Apple provider definition. Field reference and the
# issuer-scoping background live in the registry header
# (lib/onetime/sso_provider/registry.rb).
#
# ISSUER-CAPABLE via a STATIC strategy option, not discovery.
# omniauth-apple hard-codes `ISSUER = 'https://appleid.apple.com'` and
# verify_id_token! rejects any id_token whose `iss` is not exactly that
# constant (signature checked against Apple's JWKS first). The strategy does
# NOT expose the claim in the shape resolve_issuer's token-issuer branch
# reads — it nests the decoded JWT under extra.raw_info.id_info with SYMBOL
# keys — so we declare the issuer here instead. resolve_issuer precedence #1
# (strategy option :issuer) then returns it, and the identity row is keyed
# ('apple', 'https://appleid.apple.com', sub).
#
# Declaring it is truthful rather than a shortcut: the value is the same
# constant the strategy validates against, so a row can only exist if Apple
# itself asserted that issuer. `issuer` is not an option omniauth-apple reads,
# and OmniAuth strategy options are a Hashie::Mash, so the extra key is inert.
#
# ⚠️  OPERATOR PREREQUISITE — SameSite=None session cookie.
# Apple sets response_mode=form_post whenever a scope is requested, so the
# callback arrives as a CROSS-SITE POST from appleid.apple.com. A SameSite=Lax
# cookie (this app's default, site.session.same_site in
# etc/defaults/config.defaults.yaml) is withheld on cross-site POST, so the
# Rodauth session — and with it the OmniAuth state and nonce — is absent at the
# callback and the flow fails CSRF validation. Sign in with Apple therefore
# requires `site.session.same_site: none` together with `secure: true`.
# Do not drop the scope to force Apple's GET redirect instead: without
# 'email name' Apple returns no email and account creation cannot complete.
#
# The OTHER half of that cross-site POST is handled IN CODE, not by the
# operator: Rack::Protection::HttpOrigin guards the auth app and would deny
# the callback outright (403, before OmniAuth runs) because the Origin is
# appleid.apple.com and no display domain can ever equal it. Every provider
# before Apple had a GET callback, which HttpOrigin's `safe?` short-circuits,
# so nothing exercised that path. Onetime::Middleware::HttpOriginOptions now
# allows a POST to an OmniAuth CALLBACK path when the Origin is one of the
# configured IdP origins — the full rationale, and why the request phase is
# deliberately excluded, is in that file.
#
# NAME IS FIRST-AUTHORIZATION ONLY; EMAIL IS NOT. The two come from different
# places in this strategy, and conflating them leads to the wrong conclusion
# about whether repeat sign-ins work:
#
#   email       id_info[:email]                     — the id_token, EVERY time
#   first/last  user_info.dig('name', ...)          — the `user` POST param,
#                                                     sent only on the FIRST
#                                                     authorization for a
#                                                     given Services ID
#
# So account creation is not limited to a user's first sign-in; only the
# display name is. The email may be a private relay address
# (@privaterelay.appleid.com) — is_private_email in the auth hash flags it.
# Keep APPLE_TRUST_EMAIL_FOR_LINKING false: a relay address is not evidence of
# control over the underlying mailbox.
#
# ⚠️  APPLE_PRIVATE_KEY is the CONTENTS of the .p8 EC key, not a path. The
# strategy mints a fresh ES256 client-secret JWT per request from it, which is
# why there is no APPLE_CLIENT_SECRET. OpenSSL::PKey::EC must be able to parse
# it, so newlines have to survive the deployment's env plumbing — see
# .env.reference for the \n-escaped form.

module Onetime
  module SsoProvider
    module Apple
      # The one issuer omniauth-apple's verify_iss! will accept.
      ISSUER = 'https://appleid.apple.com'

      # Apple requires a scope for name/email. Space-delimited.
      SCOPE = 'email name'

      # Normalize the \n-escaped single-line form deployments commonly use for
      # multi-line secrets back into a real PEM. A value that already contains
      # newlines passes through untouched.
      #
      # @param pem [String, nil] raw APPLE_PRIVATE_KEY value
      # @return [String, nil] PEM text OpenSSL::PKey::EC can parse
      def self.normalize_pem(pem)
        return pem if pem.nil?

        pem.include?('\n') ? pem.gsub('\n', "\n") : pem
      end

      DEFINITION = {
        key: :apple,
        label: 'Apple',
        strategy: :apple,
        gem_require: 'omniauth-apple',
        issuer_capable: true,
        required_vars: %w[APPLE_CLIENT_ID APPLE_TEAM_ID APPLE_KEY_ID APPLE_PRIVATE_KEY],
        route_var: 'APPLE_ROUTE_NAME',
        route_default: 'apple',
        display_var: 'APPLE_DISPLAY_NAME',
        display_default: 'Apple',
        trust_var: 'APPLE_TRUST_EMAIL_FOR_LINKING',
        trust_default: false,
        idp_origin: ISSUER,
        # Apple is a PLATFORM provider: it is absent from
        # SsoConfig::PROVIDER_ROUTE_MAP, so tenant SSO never routes here and
        # these placeholders only ever satisfy the boot-time registration that
        # orgs_sso_enabled? forces. The pem is deliberately not a parseable
        # key — nothing can reach the request phase on this route.
        placeholder_options: {
          client_id: 'placeholder',
          client_secret: 'placeholder',
          team_id: 'placeholder',
          key_id: 'placeholder',
          pem: 'placeholder',
          issuer: ISSUER,
          scope: SCOPE,
        }.freeze,
        strategy_options: -> {
          {
            client_id: ENV.fetch('APPLE_CLIENT_ID', nil),
            # Generated per request from the .p8 key; the positional
            # client_secret slot must still be present for omniauth-oauth2.
            client_secret: '',
            team_id: ENV.fetch('APPLE_TEAM_ID', nil),
            key_id: ENV.fetch('APPLE_KEY_ID', nil),
            pem: normalize_pem(ENV.fetch('APPLE_PRIVATE_KEY', nil)),
            issuer: ISSUER,
            scope: SCOPE,
          }
        },
      }.freeze
    end
  end
end
