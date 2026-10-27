# apps/api/v3/logic/auth.rb
#
# frozen_string_literal: true

require_relative 'base'
require 'onetime/paseto'
require 'onetime/session/impersonation'

module V3
  module Logic
    # Credential exchange for the v3 API (#2427).
    module Auth
      # @api Exchange the caller's session or Basic auth API key for a
      #   short-lived PASETO v4.public bearer token. The token names the
      #   caller (its `sub` is the customer external ID), is bound to the v3
      #   API, and expires after the configured lifetime (default one hour).
      #   Present it as `Authorization: Bearer <token>` on the authenticated
      #   v3 secret routes. Refused with 403 BEARER_TOKENS_DISABLED until the
      #   operator enables bearer tokens.
      #
      # Why Basic auth may mint: the exchange is the only way a non-browser
      # client obtains a token, and it widens nothing. The API key already
      # authenticates every v2 request; the token it buys is time-boxed,
      # scoped to the v3 API and revoked by the same account events (suspension,
      # password change). Unlike POST /api/account/apitoken it replaces no
      # credential, so a leaked key cannot use it to lock the owner out.
      #
      # Why a bearer token may NOT mint: the route chain excludes pasetoauth,
      # and this class refuses it again, so a leaked token expires on schedule
      # instead of renewing itself.
      class GenerateToken < V3::Logic::Base
        SCHEMAS = { response: 'bearerToken' }.freeze

        # The strategies whose success may be exchanged. Checked here as well
        # as in routes.txt: a route edit alone must not be enough to turn a
        # bearer token into a renewable one.
        ISSUING_AUTH_METHODS = %w[sessionauth basic_auth].freeze

        attr_reader :token, :claims

        def raise_concerns
          verify_authenticated!

          raise Onetime::BearerTokensDisabled unless Onetime.auth_config.paseto_enabled?

          unless ISSUING_AUTH_METHODS.include?(strategy_result.auth_method.to_s)
            raise Onetime::Forbidden, 'Bearer tokens are issued to a session or an API key, not to another token'
          end

          # A colonel viewing the app as a customer must not walk away with a
          # credential for that customer: the overlay is read-only and ends
          # with the session; a token would outlive both.
          if impersonating?
            raise Onetime::Forbidden, 'Bearer tokens cannot be issued while impersonating'
          end

          # Tokens are API access, so they require what the API requires.
          require_entitlement!('api_access')
        end

        def process
          @token, @claims = Onetime::Paseto::AccessToken.issue(
            subject: cust.extid,
            keyring: Onetime::Paseto.keyring,
            audience: Onetime::Paseto::V3_AUDIENCE,
            issuer: Onetime::Paseto.issuer,
            ttl: Onetime.auth_config.paseto_token_ttl,
            now: issuance_time,
          )

          # The token itself is never logged; kid and jti identify it in a
          # later refusal's debug line.
          Onetime.auth_logger.info 'Issued API bearer token',
            customer: cust.extid,
            kid: claims.kid,
            jti: claims.jti,
            expires_at: claims.expires_at.to_i,
            auth_method: strategy_result.auth_method

          success_data
        end

        def success_data
          {
            record: {
              token: token,
              token_type: 'Bearer',
              expires_in: (claims.expires_at - claims.issued_at).to_i,
              expires_at: claims.expires_at.to_i,
              issued_at: claims.issued_at.to_i,
              kid: claims.kid,
              scope: claims.scope,
            },
            details: {
              subject: claims.subject,
              audience: claims.audience,
              issuer: claims.issuer,
            },
          }
        end

        private

        # The moment the token is issued: now, or one second past the account's
        # credential watermark when that is later. PasetoAuthStrategy refuses
        # `iat <= Customer#last_password_update` (fail-closed, the rule that
        # retires pre-change sessions), so a token minted in the same second as
        # a password change, or by a node whose clock trails the one that
        # stamped the change, would otherwise be refused on every request for
        # its whole life. One second past the watermark is well inside the
        # verifier's clock-skew allowance for `iat`/`nbf`, so the token works
        # at once, and nothing issued at or before the watermark is spared.
        def issuance_time(now = Time.now)
          watermark = cust.last_password_update.to_i
          return now if now.to_i > watermark

          Time.at(watermark + 1).utc
        end

        def impersonating?
          return false unless sess.respond_to?(:[])

          !Onetime::SessionImpersonation.active(sess).nil?
        end
      end
    end
  end
end
