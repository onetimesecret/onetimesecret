# lib/onetime/initializers/check_secret_verifier.rb
#
# frozen_string_literal: true

require_relative '../secret_verifier'

module Onetime
  module Initializers
    # CheckSecretVerifier initializer (C10/QS-6)
    #
    # Verifies at boot that the running SECRET is the one the datastore's
    # existing ciphertexts were written under, via the HKDF-derived verifier
    # in Onetime::SecretVerifier. Without this, an operator who loses .env,
    # regenerates secrets, or points the app at a restored dump gets a clean
    # boot and a working-looking site while every pre-rotation ciphertext is
    # silently unrecoverable.
    #
    # Policy (site.secret_verifier_mode):
    #   warn (default) - log loudly on mismatch, keep booting
    #   enforce        - raise SecretVerifierMismatch (FatalBootError)
    #   off            - skip the check entirely (escape hatch for exotic
    #                    multi-tenant datastore setups)
    #
    # Runtime state set:
    # - Onetime.secret_verifier_state (:ok | :adopted | :mismatch | :unavailable)
    #
    class CheckSecretVerifier < Onetime::Boot::Initializer
      @depends_on = [:familia_config]
      @provides   = [:secret_verifier]

      def should_skip?
        Onetime::SecretVerifier.mode == 'off'
      end

      def execute(_context)
        case Onetime::SecretVerifier.check!
        when :adopted
          OT.boot_logger.info '[secret_verifier] No key verifier stored; adopted one for the running SECRET'
        when :ok
          OT.boot_logger.debug '[secret_verifier] Stored key verifier matches the running SECRET'
        when :unavailable
          # Connectivity failures are doctor's and the connection pool's
          # problem; never add a second boot failure for the same cause.
          OT.boot_logger.debug '[secret_verifier] Datastore unreachable; key verifier not checked'
        when :mismatch
          OT.boot_logger.error <<~MSG.chomp
            [secret_verifier] SECRET MISMATCH: the running SECRET is not the one this datastore's existing data was encrypted with.
              Likely causes:
                - SECRET was changed/regenerated under existing data (lost .env, rerun of secret generation)
                - the app is pointed at another install's datastore (restored dump, wrong REDIS/VALKEY URL)
              Until fixed, existing secrets CANNOT be decrypted. New secrets will work but existing ones are unreadable.
              Fix:
                - restore the previous SECRET in .env and restart, or
                - if the rotation was intentional: CONFIRM=yes bundle exec rake ots:secrets:adopt
              (Reveals fail safe: no secret is consumed by a decrypt that cannot succeed.)
          MSG

          if Onetime::SecretVerifier.mode == 'enforce'
            raise Onetime::SecretVerifierMismatch,
              'SECRET does not match the datastore key verifier (site.secret_verifier_mode: enforce)'
          end
        end
      end
    end
  end
end
