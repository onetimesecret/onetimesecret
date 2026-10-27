# lib/onetime/application/auth_strategies/paseto_auth_strategy.rb
#
# frozen_string_literal: true

#
# Bearer token strategy: PASETO v4.public tokens issued by POST /api/v3/token.
#
# Routes: auth=pasetoauth (chained after sessionauth on the v3 secret routes)
# Access: `Authorization: Bearer v4.public...` with a valid, unexpired token
# User: the Customer named by the token's `sub` (an extid)
#
# ## Chain semantics
#
# The strategy only ever claims a `Bearer` credential:
#
# - No Authorization header, or another scheme (`Basic ...`): a plain
#   failure. The request is not ours; the next strategy in the chain
#   decides, exactly as it would have before this strategy existed.
# - auth.paseto.enabled is off: a plain failure too, whatever the header
#   says. A disabled strategy behaves as if it were not registered, so a
#   deployment that never opted in sees no change at all (the stable v3
#   surface accepts sessions and explicit guest routes only).
# - A `Bearer` token that is presented and rejected: a TERMINAL failure
#   (Helpers#credentialed_failure, 401 with a `Bearer` challenge), so an
#   invalid token can never degrade to anonymous on a noauth-capable chain.
#   The one carve-out is the shared one: a valid session on the same request
#   outranks the rejected header, as it does for Basic.
#
# ## What is checked, in order
#
# 1. The token parses as v4.public and its footer names a key this
#    deployment holds (current SECRET, or a SECRET_PREVIOUS entry).
# 2. The Ed25519 signature verifies under that key.
# 3. The claims: `exp` in the future, `nbf`/`iat` not in the future, `aud`
#    is the v3 API, `iss` is this deployment, `scope` is `["*"]`.
# 4. `sub` is a well-formed customer extid that loads.
# 5. The account is not suspended, and the token was issued after the
#    account's last credential change (Customer#last_password_update, the
#    same watermark that retires sessions): changing a password revokes
#    every outstanding token.
#
# Verification is a signature check and two hash lookups (kid, extid);
# nothing compares a caller-supplied value against a stored secret, so there
# is no secret-dependent branch to time.
#
# @see Onetime::Paseto::AccessToken for the claims and the key selection
# @see Onetime::Application::AuthStrategies

require_relative 'helpers'
require_relative '../../paseto'

module Onetime
  module Application
    module AuthStrategies
      class PasetoAuthStrategy < Otto::Security::AuthStrategy
        include Helpers
        include Onetime::Application::OrganizationLoader

        @auth_method_name = 'pasetoauth'

        class << self
          attr_reader :auth_method_name
        end

        # RFC 6750 §2.1: `Bearer` 1*SP b64token. The scheme name is
        # case-insensitive (RFC 9110 §11.1); the token is taken verbatim.
        BEARER_HEADER = %r{\ABearer[ \t]+(?<token>[A-Za-z0-9._~+/=-]+)[ \t]*\z}i

        SCHEME = Onetime::SessionFailureCode::SCHEME_BEARER

        # @param audience [String] the `aud` this strategy accepts
        def initialize(audience: Onetime::Paseto::V3_AUDIENCE)
          super()
          @audience = audience
        end

        def authenticate(env, _requirement)
          header = env['HTTP_AUTHORIZATION']
          return failure('[AUTH_HEADER_MISSING] No authorization header') if header.nil? || header.empty?

          match = BEARER_HEADER.match(header)
          return failure('[AUTH_TYPE_MISMATCH] Not a bearer token') unless match
          return failure('[PASETO_DISABLED] Bearer tokens are not enabled') unless enabled?

          claims = verify_token(match[:token], env)
          return claims if claims.is_a?(Otto::Security::Authentication::AuthFailure)

          cust = load_subject(claims.subject)
          unless cust
            OT.ld '[pasetoauth] Token subject does not resolve', kid: claims.kid, jti: claims.jti
            return credentialed_failure('[TOKEN_INVALID] Invalid token', env, code: :api_token_invalid, scheme: SCHEME)
          end

          # Checked after the signature, so only a holder of a valid token can
          # observe the account state (non-enumerating), mirroring Basic auth.
          if cust.suspended?
            return credentialed_failure(
              '[ACCOUNT_SUSPENDED] Account suspended',
              env,
              code: :suspended_credentials,
              scheme: SCHEME,
            )
          end

          if predates_credential_change?(cust, claims)
            OT.ld '[pasetoauth] Token predates credential change', customer: cust.extid, kid: claims.kid, jti: claims.jti
            return credentialed_failure('[TOKEN_INVALID] Invalid token', env, code: :api_token_invalid, scheme: SCHEME)
          end

          OT.ld "[pasetoauth] Authenticated '#{cust.extid}' via bearer token", kid: claims.kid, jti: claims.jti

          # The Rack session when the stack provides one (an API client with a
          # cookie jar), nil for a stateless call; see BasicAuthStrategy for
          # why no `{}` fallback is fabricated here.
          session     = env['rack.session']
          org_context = load_organization_context(cust, session, env)

          token_metadata = {
            auth_type: 'paseto',
            token_kid: claims.kid,
            token_jti: claims.jti,
            token_expires_at: claims.expires_at.to_i,
          }
          metadata_hash  = build_metadata(env, token_metadata).merge(organization_context: org_context)

          success(
            session: session,
            user: cust,
            auth_method: self.class.auth_method_name,
            **metadata_hash,
          )
        rescue Onetime::Paseto::KeyringUnavailable => ex
          # A boot that never derived keys cannot verify anything: refuse the
          # presented credential rather than letting it fall through.
          OT.le "[pasetoauth] #{ex.message}"
          credentialed_failure('[TOKEN_INVALID] Invalid token', env, code: :api_token_invalid, scheme: SCHEME)
        end

        protected

        def enabled?
          Onetime.auth_config.paseto_enabled?
        end

        # @param token [String] the bearer token as presented
        # @param env [Hash] the Rack env, for the credentialed failure
        # @return [Onetime::Paseto::AccessToken::Claims, Otto::Security::Authentication::AuthFailure]
        def verify_token(token, env)
          Onetime::Paseto::AccessToken.verify(
            token,
            keyring: Onetime::Paseto.keyring,
            audience: @audience,
            issuer: Onetime::Paseto.issuer,
          )
        rescue Onetime::Paseto::TokenExpired => ex
          OT.ld "[pasetoauth] Rejected bearer token: #{ex.message}"
          credentialed_failure('[TOKEN_EXPIRED] Token expired', env, code: :api_token_expired, scheme: SCHEME)
        rescue Onetime::Paseto::KeyringUnavailable
          raise
        rescue Onetime::Paseto::Error => ex
          # The reason stays in the debug log; the client learns only that the
          # token was rejected (one code for the whole family, as for Basic).
          OT.ld "[pasetoauth] Rejected bearer token: #{ex.class.name.split('::').last}: #{ex.message}"
          credentialed_failure('[TOKEN_INVALID] Invalid token', env, code: :api_token_invalid, scheme: SCHEME)
        end

        def load_subject(extid)
          return nil unless Onetime::Customer.extid?(extid)

          Onetime::Customer.find_by_extid(extid)
        end

        # A token minted before the account's last password change is retired
        # the way a session authenticated before it is
        # (Onetime::CustomerSessionEvaluator#predates_credential_change?).
        def predates_credential_change?(cust, claims)
          watermark = cust.last_password_update.to_i
          return false unless watermark.positive?

          claims.issued_at.to_i <= watermark
        end
      end
    end
  end
end
