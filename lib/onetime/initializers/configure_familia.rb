# lib/onetime/initializers/configure_familia.rb
#
# frozen_string_literal: true

require 'digest'
require 'base64'

module Onetime
  module Initializers
    # ConfigureFamilia initializer
    #
    # Configures Familia's URI early in the boot process. Without this,
    # Familia.uri defaults to redis://127.0.0.1:6379 which causes connection
    # failures in Docker environments where Redis/Valkey is on a different host.
    #
    # This initializer configures external library state and doesn't set runtime
    # state that needs to be tracked.
    #
    class ConfigureFamilia < Onetime::Boot::Initializer
      @depends_on = [:logging]
      @provides   = [:familia_config]

      def execute(_context)
        secret_key = OT.conf.dig('site', 'secret')
        raise 'site.secret not set or empty' if secret_key.to_s.empty?

        uri = OT.conf.dig('redis', 'uri') || ''

        # Strip surrounding quotes that may have been introduced via ENV var
        # misconfiguration (e.g., REDIS_URL="redis://..." instead of REDIS_URL=redis://...)
        # This prevents URI::InvalidURIError: bad URI (is not URI?)
        uri = uri.to_s.strip.gsub(/\A["']|["']\z/, '')

        # Early validation: Check if Redis URI is properly configured
        raise_error = if uri.empty?
          OT.boot_logger.fatal '[configure_familia] Invalid URI'
        elsif uri.include?('CHANGEME')
          OT.boot_logger.warn "[configure_familia] WARNING: Redis password is 'CHANGEME'"
        end

        raise Onetime::Problem, "Redis URI not configured (#{uri})" if raise_error

        # Test environment safety: Ensure tests use port 2121
        if ENV['RACK_ENV'] == 'test' && !uri.include?(':2121')
          raise Onetime::Problem, "Test environment MUST use Redis port 2121, got: #{uri}. Set VALKEY_URL='valkey://127.0.0.1:2121/0'"
        end

        # Set Familia's URI so it's available for isolated connections
        # during legacy data detection and other pre-connection operations
        Familia.uri = uri

        # Encryption keys with versioning for key rotation.
        #
        # v1: Legacy SHA-256 derivation (reads existing encrypted data)
        # v2: HKDF derivation (RFC 5869, used for new writes)
        #
        # Familia expects base64-encoded 32-byte keys.
        require 'onetime/key_derivation'

        v1_key = Base64.strict_encode64(Digest::SHA256.digest(secret_key))
        v2_key = Onetime::KeyDerivation.derive_base64(secret_key, :familia_enc)

        Familia.config.encryption_keys     = {
          v1: v1_key,
          v2: v2_key,
        }
        Familia.config.current_key_version = :v2

        # Identifier signing secret for Familia::VerifiableIdentifier, which HMACs
        # Secret/Receipt objids. Familia >= 2.11 removed its committed fallback key
        # and rejects a missing OR blank secret (delano/familia#335), raising at
        # the first identifier mint. IDENTIFIER_SECRET is optional in our config,
        # and the compose files inject `IDENTIFIER_SECRET=${IDENTIFIER_SECRET:-}` --
        # an empty string whenever the outer variable is unset. So derive a stable
        # per-deployment value from site.secret when the env var is absent or blank,
        # using the same HKDF purpose (:identifier) that init.rake writes to .env:
        # installs that ran init and those that did not converge on one key.
        #
        # Safe to set per deployment: nothing reads identifiers back through
        # Familia::VerifiableIdentifier.verified_identifier? yet, so tags minted
        # under any prior (committed-fallback or empty) key still resolve. Revisit
        # if verification-on-read is ever introduced -- tracked in issue #3630.
        identifier_secret                  = ENV['IDENTIFIER_SECRET'].to_s
        if identifier_secret.empty?
          identifier_secret = Onetime::KeyDerivation.derive_hex(secret_key, :identifier)
        end
        ENV['VERIFIABLE_ID_HMAC_SECRET'] ||= identifier_secret

        # Pin the cryptographic domain-separation inputs explicitly instead of
        # relying on Familia's library defaults, so an upstream default change
        # can never silently strand ciphertext.
        #
        # encryption_personalization feeds BLAKE2b key derivation for
        # XChaCha20-Poly1305 (used once rbnacl/libsodium are present). It is
        # PERMANENT: Familia has no rotation/history mechanism for it, so
        # changing this value makes every existing XChaCha20 envelope
        # undecryptable. 'FamilialMatters' is Familia's long-standing default
        # and therefore the only value compatible with any XChaCha20 data an
        # installation may already hold.
        Familia.config.encryption_personalization = 'FamilialMatters'

        # encryption_hkdf_salt feeds HKDF-SHA256 key derivation for
        # AES-256-GCM. All AES envelopes written by familia <= 2.10.x used the
        # then-hardcoded salt 'FamiliaEncryption'; familia >= 2.11 changes the
        # default to 'FamilialMatters' and only *falls back* to the legacy
        # value on decrypt. Pinning the legacy value keeps any AES writes
        # byte-compatible with existing data and with familia 2.10.x nodes
        # (mixed fleets / rollback), and makes legacy decrypts succeed on the
        # first salt candidate instead of the fallback. Rotating this later is
        # supported via encryption_hkdf_salt_history.
        # (Guarded: the knob only exists in familia >= 2.11.)
        if Familia.config.respond_to?(:encryption_hkdf_salt=)
          Familia.config.encryption_hkdf_salt         = 'FamiliaEncryption'
          # Defensive: any AES envelope written by an unpinned familia >= 2.11
          # (e.g. a dev build before this initializer pinned the salt) used the
          # library default 'FamilialMatters'. Keeping it in the history makes
          # such data decryptable; it costs one extra KDF attempt only when the
          # first candidate fails.
          Familia.config.encryption_hkdf_salt_history = ['FamilialMatters']
        end

        OT.boot_logger.debug "[init] Configure Familia URI: #{uri}"
      end
    end
  end
end
