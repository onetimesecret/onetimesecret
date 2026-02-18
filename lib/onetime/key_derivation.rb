# lib/onetime/key_derivation.rb
#
# frozen_string_literal: true

require 'openssl'
require 'base64'

module Onetime
  # Centralized HKDF-based key derivation (RFC 5869).
  #
  # All purpose-specific keys are derived from a single root SECRET
  # using OpenSSL::KDF.hkdf with explicit context strings. Cryptographic
  # separation is guaranteed by distinct `info` values.
  #
  # The versioned salt allows changing the derivation scheme in future
  # major versions without breaking existing installations (bump the
  # salt, keep the old one for migration).
  #
  #   SECRET (64 random bytes, operator-provided or generated)
  #       ├── session        ← HKDF(SECRET, info="session",       len=64)
  #       ├── familia-enc    ← HKDF(SECRET, info="familia-enc",   len=32)
  #       ├── argon2-pepper  ← HKDF(SECRET, info="argon2-pepper", len=32)
  #       └── federation     ← HKDF(SECRET, info="federation",    len=32)
  #
  module KeyDerivation
    SALT = 'onetimesecret-v1'

    PURPOSES = {
      session:       { info: 'session',       length: 64 },
      familia_enc:   { info: 'familia-enc',   length: 32 },
      argon2_pepper: { info: 'argon2-pepper', length: 32 },
      federation:    { info: 'federation',    length: 32 },
    }.freeze

    # Derive raw bytes for a given purpose.
    #
    # @param secret [String] root secret (any length, but 64+ bytes recommended)
    # @param purpose [Symbol] one of PURPOSES keys
    # @param salt [String] override salt (default: SALT)
    # @return [String] raw derived key bytes
    def self.derive(secret, purpose, salt: SALT)
      config = PURPOSES.fetch(purpose) do
        raise ArgumentError, "unknown purpose: #{purpose.inspect}"
      end

      OpenSSL::KDF.hkdf(
        secret.to_s,
        salt: salt,
        info: config[:info],
        length: config[:length],
        hash: 'SHA256'
      )
    end

    # Derive and return as hex string.
    def self.derive_hex(secret, purpose, salt: SALT)
      derive(secret, purpose, salt: salt).unpack1('H*')
    end

    # Derive and return as strict Base64 (no newlines).
    def self.derive_base64(secret, purpose, salt: SALT)
      Base64.strict_encode64(derive(secret, purpose, salt: salt))
    end

    # Convenience: derive a session-internal subkey via HKDF.
    # Used by Onetime::Session to get hmac / encryption keys from
    # the session secret.
    #
    # @param session_secret [String] the session master secret
    # @param sub_purpose [String] e.g. "hmac", "encryption"
    # @return [String] hex-encoded 32-byte key
    def self.derive_session_subkey(session_secret, sub_purpose)
      raw = OpenSSL::KDF.hkdf(
        session_secret.to_s,
        salt: SALT,
        info: "session-#{sub_purpose}",
        length: 32,
        hash: 'SHA256'
      )
      raw.unpack1('H*')
    end
  end
end
