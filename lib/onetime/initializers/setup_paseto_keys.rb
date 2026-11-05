# lib/onetime/initializers/setup_paseto_keys.rb
#
# frozen_string_literal: true

require_relative '../paseto'

module Onetime
  module Initializers
    # SetupPasetoKeys initializer
    #
    # Derives the Ed25519 keyring the v3 API bearer tokens (PASETO
    # v4.public, #2427) are signed and verified with. Pure derivation from
    # the root SECRET and SECRET_PREVIOUS (Onetime::Paseto::Keyring.derive),
    # so it needs no datastore and runs in database-less boots too.
    #
    # It runs whether or not auth.paseto.enabled is set: the derivation is
    # cheap, the result is read only when a token is issued or presented, and
    # keeping it unconditional lets the operator flag change at runtime (and
    # lets tests flip it per example) without a second boot.
    #
    # Without a secret there is nothing to derive from, and the boot goes on
    # without a keyring rather than stopping here: Onetime::Config.after_load
    # admits an empty site.secret under development.allow_nil_global_secret
    # (with its warning), and bearer tokens are an optional feature that must
    # not take that boot down. The gap is closed at request time, not open:
    # Onetime::Paseto.keyring raises KeyringUnavailable, which
    # PasetoAuthStrategy answers with a terminal refusal of every presented
    # token and POST /api/v3/token with a 500, never a token.
    #
    # Runtime state set:
    # - Onetime::Runtime.security.paseto_keyring (nil when no secret is set)
    #
    class SetupPasetoKeys < Onetime::Boot::Initializer
      @depends_on = [:logging, :secrets]
      @provides   = [:paseto_keys]

      def execute(_context)
        secret = OT.conf.dig('site', 'secret')
        if secret.to_s.empty?
          Onetime::Runtime.update_security(paseto_keyring: nil)
          OT.boot_logger.warn 'PASETO keyring not derived: site.secret is empty; ' \
                              'bearer tokens cannot be issued or verified until SECRET is set'
          return
        end

        keyring = Onetime::Paseto::Keyring.derive(secret, ENV.fetch('SECRET_PREVIOUS', nil))
        Onetime::Runtime.update_security(paseto_keyring: keyring)

        OT.boot_logger.debug 'Derived PASETO signing keyring',
          signing_kid: keyring.signing_key.kid,
          accepted_kids: keyring.kids
      end
    end
  end
end
