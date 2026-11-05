# lib/onetime/paseto.rb
#
# frozen_string_literal: true

# PASETO v4.public bearer tokens for the v3 API (#2427).
#
# Layout:
#   paseto/v4_public.rb     the token format: Ed25519 over PAE, base64url
#   paseto/keyring.rb       keys derived from SECRET (+ SECRET_PREVIOUS)
#   paseto/access_token.rb  registered claims: issue and verify
#
# The keyring is built once at boot by Onetime::Initializers::SetupPasetoKeys
# and read here from Onetime::Runtime.security. Whether tokens are accepted
# or issued at all is a per-request decision on Onetime.auth_config
# (paseto_enabled?), so the operator flag can change without a code change
# and the strategy stays registered either way.

module Onetime
  module Paseto
    class Error < StandardError; end

    # The token is not a decodable v4.public token.
    class MalformedToken < Error; end

    # The footer names no key this deployment holds.
    class UnknownKey < Error; end

    class InvalidSignature < Error; end

    # Signature valid, claims unacceptable.
    class InvalidClaims < Error; end

    # Signature valid, `exp` has passed. Separate from InvalidClaims because
    # a client acts on it differently (mint a new token, no alarm).
    class TokenExpired < InvalidClaims; end

    # The boot did not derive a keyring (SetupPasetoKeys has not run).
    class KeyringUnavailable < Error; end

    # The audience the v3 API issues and accepts. A token minted here is
    # refused by any verifier expecting another surface.
    V3_AUDIENCE = 'onetimesecret:api:v3'

    class << self
      # @return [Keyring]
      # @raise [KeyringUnavailable]
      def keyring
        Onetime::Runtime.security.paseto_keyring ||
          raise(KeyringUnavailable, 'PASETO keyring not derived; SetupPasetoKeys has not run')
      end

      # The `iss` claim: the deployment's canonical host. Each region (and
      # each self-hosted install) issues under its own name, so a token is
      # tied to the deployment that minted it even where SECRETs coincide.
      #
      # @return [String]
      def issuer
        host = OT.conf&.dig('site', 'host').to_s.strip
        host.empty? ? 'onetimesecret' : host
      end
    end
  end
end

require_relative 'paseto/v4_public'
require_relative 'paseto/keyring'
require_relative 'paseto/access_token'
