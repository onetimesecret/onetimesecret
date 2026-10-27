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
    # Runtime state set:
    # - Onetime::Runtime.security.paseto_keyring
    #
    class SetupPasetoKeys < Onetime::Boot::Initializer
      @depends_on = [:logging, :secrets]
      @provides   = [:paseto_keys]

      def execute(_context)
        secret = OT.conf.dig('site', 'secret')
        raise Onetime::Problem, 'site.secret not set or empty' if secret.to_s.empty?

        keyring = Onetime::Paseto::Keyring.derive(secret, ENV.fetch('SECRET_PREVIOUS', nil))
        Onetime::Runtime.update_security(paseto_keyring: keyring)

        OT.boot_logger.debug 'Derived PASETO signing keyring',
          signing_kid: keyring.signing_key.kid,
          accepted_kids: keyring.kids
      end
    end
  end
end
