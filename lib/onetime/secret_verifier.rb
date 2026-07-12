# lib/onetime/secret_verifier.rb
#
# frozen_string_literal: true

require_relative 'key_derivation'

module Onetime
  # Binds the running SECRET to the data it encrypted (C10/QS-6).
  #
  # An HKDF-derived, purpose-separated verifier (KeyDerivation :key_verifier)
  # is stored as a plain string in the models logical DB. At boot,
  # CheckSecretVerifier compares the stored value against the one derived
  # from the running SECRET:
  #
  #   absent    -> adopt (SET NX): first boot and post-flush both land here.
  #                If the key was flushed along with everything else, there
  #                is nothing left to protect and re-adoption is correct.
  #   equal     -> :ok
  #   different -> :mismatch: the SECRET changed under existing data, or the
  #                app points at another install's datastore. Every
  #                pre-rotation ciphertext is unrecoverable until the key is
  #                restored (or the rotation is confirmed via
  #                `rake ots:secrets:adopt`).
  #
  # The verifier is one-way: it is not equal to any working key, and
  # publishing it reveals nothing about SECRET beyond an offline-guessing
  # oracle — irrelevant for the 64-random-byte SECRETs `rake ots:secrets`
  # generates, and no worse than any stored ciphertext for operator-chosen
  # weak secrets.
  module SecretVerifier
    # Plain Valkey string key, no TTL, models logical DB (Familia default
    # connection).
    VERIFIER_KEY = 'onetime:secret_verifier'

    MODES = %w[warn enforce off].freeze

    extend self

    # Hex-encoded verifier derived from the given (default: configured) SECRET.
    #
    # @param secret [String, nil] root secret; defaults to site.secret
    # @return [String] hex-encoded 32-byte verifier
    def expected_verifier(secret = nil)
      secret ||= OT.conf.dig('site', 'secret')
      Onetime::KeyDerivation.derive_hex(secret, :key_verifier)
    end

    # The stored verifier, or nil when never adopted. Raises on connection
    # errors — callers decide how to degrade.
    def stored_verifier
      Familia.dbclient.get(VERIFIER_KEY)
    end

    # Policy knob: site.secret_verifier_mode (warn | enforce | off).
    # Unset or unrecognized values fall back to 'warn' — halting by default
    # would brick running deploys on their first upgrade to this code.
    def mode
      configured = OT.conf.dig('site', 'secret_verifier_mode').to_s
      MODES.include?(configured) ? configured : 'warn'
    end

    # Boot-time check: adopt when absent, compare when present. Caches the
    # result on Onetime.secret_verifier_state and returns it. Never raises:
    # connectivity failures are doctor's and the connection pool's problem —
    # this check must not add a second boot failure for the same cause.
    #
    # @return [Symbol] :adopted | :ok | :mismatch | :unavailable
    def check!
      expected = expected_verifier
      stored   = stored_verifier

      state = if stored.nil?
                # SET NX so a concurrent first boot can't stomp an adoption;
                # on a lost race, fall through to comparing the winner's value.
                if Familia.dbclient.set(VERIFIER_KEY, expected, nx: true)
                  :adopted
                else
                  stored_verifier == expected ? :ok : :mismatch
                end
              elsif stored == expected
                :ok
              else
                :mismatch
              end

      Onetime.secret_verifier_state = state
      state
    rescue StandardError => ex
      OT.ld "[secret_verifier] datastore unavailable: #{ex.class}: #{ex.message}"
      Onetime.secret_verifier_state = :unavailable
      :unavailable
    end

    # Read-only comparison for `rake ots:secrets:verify` — never adopts, so
    # "never adopted" stays observable as its own condition.
    #
    # @return [Symbol] :ok | :mismatch | :unadopted | :unavailable
    def status
      stored = stored_verifier
      return :unadopted if stored.nil?

      stored == expected_verifier ? :ok : :mismatch
    rescue StandardError => ex
      OT.ld "[secret_verifier] datastore unavailable: #{ex.class}: #{ex.message}"
      :unavailable
    end

    # Unconditionally re-stamp the verifier for the running SECRET (used by
    # `rake ots:secrets:adopt` after an intentional rotation). Raises on
    # connection errors — an adopt that didn't happen must not look like one.
    #
    # @return [String] the newly stored hex verifier
    def adopt!
      expected                      = expected_verifier
      Familia.dbclient.set(VERIFIER_KEY, expected)
      Onetime.secret_verifier_state = :ok
      expected
    end
  end
end
