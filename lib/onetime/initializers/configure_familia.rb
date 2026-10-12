# lib/onetime/initializers/configure_familia.rb
#
# frozen_string_literal: true

require 'ipaddr'
require 'uri'
require_relative '../key_derivation'

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

      # Build the Familia encryption-key map and the version tag for new
      # writes (C10 §3.3 rotation chain). Pure so the mapping is unit-testable
      # without booting.
      #
      # No SECRET_PREVIOUS (the overwhelmingly common case): v2 (HKDF)
      # derives from the current SECRET and writes are tagged :v2. (The
      # legacy v1 unsalted-SHA-256 decrypt fallback was retired 2026-07-18 once
      # the TTL window closed on all v1-tagged data — see
      # docs/security/assessment-2026-06-22/resolutions/C6-*.md.)
      #
      # SECRET_PREVIOUS set (comma-separated, OLDEST first — append the
      # outgoing SECRET on each rotation; docs/runbooks/secret-rotation.md):
      #   - :v2 maps to the OLDEST previous secret's derived key. Every
      #     v2-tagged envelope predates the first rotation (each rotation
      #     moves writes onto a content-addressed tag), so they were all
      #     written under that secret.
      #   - every previous secret also registers decrypt-only under its own
      #     content-addressed tag, so envelopes written between rotations
      #     keep decrypting.
      #   - the current SECRET registers under its content-addressed tag,
      #     which becomes the tag for new writes. Content-addressing (first
      #     8 hex of the :key_verifier derivation) makes every generation's
      #     tag unambiguous with no rotation counter to persist.
      #
      # @param secret_key [String] the current root SECRET
      # @param previous_csv [String, nil] comma-separated previous SECRETs
      # @return [(Hash{Symbol => String}, Symbol)] keys map and current tag
      def self.build_encryption_keys(secret_key, previous_csv = nil)
        previous = previous_csv.to_s.split(',').map(&:strip).reject(&:empty?)

        if previous.empty?
          keys = {
            v2: Onetime::KeyDerivation.derive_base64(secret_key, :familia_enc),
          }
          return [keys, :v2]
        end

        oldest = previous.first
        keys   = {
          v2: Onetime::KeyDerivation.derive_base64(oldest, :familia_enc),
        }
        previous.each do |prev|
          keys[content_tag(prev)] = Onetime::KeyDerivation.derive_base64(prev, :familia_enc)
        end

        current_tag       = content_tag(secret_key)
        keys[current_tag] = Onetime::KeyDerivation.derive_base64(secret_key, :familia_enc)
        [keys, current_tag]
      end

      # Content-addressed envelope version tag for a secret: :"r<first-8-hex>"
      # of its :key_verifier derivation (same purpose the boot verifier uses,
      # so tag and stored verifier stay derivable from one another).
      def self.content_tag(secret)
        :"r#{Onetime::KeyDerivation.derive_hex(secret, :key_verifier)[0, 8]}"
      end

      # URI schemes whose connections use TLS. URI::Valkey (uri-valkey, which
      # familia loads) sets `ssl:` in #conf from exactly these, and both the
      # connection pool (setup_connection_pool.rb) and Familia's own clients
      # build their Redis config from #conf.
      REDIS_TLS_SCHEMES = %w[rediss valkeys].freeze

      # RFC 6598 shared address space (carrier-grade NAT), private in practice
      # but outside IPAddr#private? (RFC 1918, fc00::/7) and #link_local?
      # (169.254.0.0/16, fe80::/10).
      CGNAT_RANGE = IPAddr.new('100.64.0.0/10').freeze

      # Query keys that change WHERE the client connects. URI::Valkey#conf
      # merges every query parameter over the URI's own host, port and ssl
      # (uri-valkey 1.4.0), and redis-client 0.30's Config takes `path` over
      # `host` (a unix socket) and a `url`'s host only when `host` is absent.
      REDIS_TARGET_PARAMS = %w[host path url].freeze

      # A single-label hostname that can only be a name (a compose or k8s
      # service such as `maindb`): it starts with a letter. An all-digit or
      # 0x-prefixed label is not one: the resolver reads `134744072` and
      # `0x8080808` as IPv4 addresses (8.8.8.8).
      SINGLE_LABEL_HOSTNAME = /\A[a-z][a-z0-9_-]*\z/

      # Classify how a Redis/Valkey URI reaches the datastore
      # (RISK-2026-08-14-L07). Pure so the boot check is unit-testable without
      # booting; reads only the scheme, host and query, never the userinfo.
      #
      #   :tls                rediss:// or valkeys://, no `ssl` query parameter
      #   :local_plaintext    anything else to a loopback host (127.0.0.0/8,
      #                       ::1, localhost) or a unix socket (unix://, or a
      #                       `path` query parameter)
      #   :private_plaintext  anything else to a host on a private network: a
      #                       single-label name (a compose/k8s service such as
      #                       `maindb`) or a private, CGNAT or link-local IP
      #                       literal (RFC 1918, 100.64/10, 169.254/16, fc00::/7,
      #                       fe80::/10)
      #   :remote_plaintext   anything else: a dotted hostname, a public or
      #                       numeric-form IP, a target the client would take
      #                       from a `url` parameter, a repeated target
      #                       parameter, or a URI that does not parse
      #
      # The host graded is the one the client connects to, not the URI's
      # authority: a `host` query parameter replaces it and a `path` one turns
      # the connection into a unix socket (SEC-B04: `redis://127.0.0.1/0?host=
      # db.example.com` connects to db.example.com). An `ssl` query parameter
      # is merged OVER the scheme the same way (a bare `?ssl` turns TLS off
      # even on rediss://), so a URI carrying one is never :tls: the scheme
      # alone is what this asserts. A hostname is never resolved, so a dotted
      # name that happens to resolve privately is still :remote_plaintext; the
      # boot check only grades how loudly to say so.
      #
      # @param uri [String, nil]
      # @return [Symbol] :tls, :local_plaintext, :private_plaintext or
      #   :remote_plaintext
      def self.redis_transport(uri)
        parsed = URI.parse(uri.to_s.strip)
        scheme = parsed.scheme.to_s.downcase
        return :local_plaintext if scheme == 'unix'

        params = redis_query_params(parsed.query)
        return :tls if REDIS_TLS_SCHEMES.include?(scheme) && !params.key?('ssl')

        redis_target_transport(parsed.hostname, params)
      rescue URI::Error
        :remote_plaintext
      end

      # Query parameters split the way URI::Valkey#conf splits them (on & or
      # ;, `key=value`, a bare `key` has a nil value). A key given twice maps
      # to :repeated: conf would pass the client an Array.
      #
      # @param query [String, nil]
      # @return [Hash{String => String, nil, Symbol}]
      def self.redis_query_params(query)
        query.to_s.split(/[&;] */).each_with_object({}) do |pair, params|
          key, value  = pair.split('=', 2)
          params[key] = params.key?(key) ? :repeated : value
        end
      end

      # Grade the connection target redis-client will use for a non-TLS URI.
      #
      # @param uri_host [String, nil] the URI's own hostname
      # @param params [Hash] from .redis_query_params
      # @return [Symbol]
      def self.redis_target_transport(uri_host, params)
        return :remote_plaintext if REDIS_TARGET_PARAMS.any? { |key| params[key] == :repeated }
        return :local_plaintext if params['path'] # a unix socket wins over any host

        host = params.key?('host') ? params['host'] : uri_host
        # No host: the client would take one from a `url` parameter, which
        # this does not interpret, or connect to whatever an empty host means.
        return :remote_plaintext if host.to_s.empty?
        return :local_plaintext if loopback_host?(host)

        private_host?(host) ? :private_plaintext : :remote_plaintext
      end

      # @param host [String, nil] a URI hostname (IPv6 without brackets)
      # @return [Boolean]
      def self.loopback_host?(host)
        name = host.to_s.downcase
        return false if name.empty?
        return true if name == 'localhost'

        IPAddr.new(name).loopback?
      rescue IPAddr::Error
        false
      end

      # A single-label hostname, or a private, CGNAT or link-local IP literal
      # (an IPv4-mapped IPv6 literal is judged as its IPv4 address).
      #
      # @param host [String, nil] a URI hostname (IPv6 without brackets)
      # @return [Boolean]
      def self.private_host?(host)
        name = host.to_s.downcase
        return false if name.empty?

        address = IPAddr.new(name).native
        address.private? || address.link_local? || CGNAT_RANGE.include?(address)
      rescue IPAddr::Error
        # Not a standard IP literal: private only as a single-label NAME. A
        # dotted name, or a numeric form IPAddr rejects but the resolver
        # accepts (`134744072`, `0x8080808`), is not.
        name.match?(SINGLE_LABEL_HOSTNAME)
      end

      # redis.require_tls as a boolean. The shipped default renders a real
      # boolean; a hand-written 'true' string also counts, since reading it as
      # false would silently skip the requirement.
      def self.redis_require_tls?(value)
        value == true || value.to_s.strip.casecmp?('true')
      end

      # Enforce redis.require_tls, or report plaintext to a non-loopback host.
      #
      #   require_tls, URI not :tls     -> raise Onetime::Problem
      #   :remote_plaintext otherwise   -> one warning, boot continues
      #   :private_plaintext otherwise  -> one info line (the default compose
      #                                    stack's `maindb` lands here; a
      #                                    warning on every default boot would
      #                                    teach operators to ignore it)
      #   anything else                 -> silent
      #
      # Both messages carry the URI through redact_uri_userinfo, which masks
      # the userinfo (password) and the query (which can carry one too).
      #
      # @param uri [String]
      # @param require_tls [Boolean]
      # @param logger [#warn, #info]
      # @return [Symbol] the transport classification
      # @raise [Onetime::Problem] when TLS is required and the URI lacks it
      def self.check_redis_transport!(uri, require_tls:, logger: OT.boot_logger)
        transport = redis_transport(uri)

        if require_tls && transport != :tls
          raise Onetime::Problem,
            'redis.require_tls is enabled but the Redis/Valkey URI does not use TLS ' \
            "(#{OT::Utils.redact_uri_userinfo(uri)}). Use a rediss:// or valkeys:// URI " \
            'without an `ssl` query parameter, or unset VALKEY_REQUIRE_TLS / REDIS_REQUIRE_TLS.'
        end

        case transport
        when :remote_plaintext
          logger.warn '[configure_familia] Redis/Valkey URI does not use TLS and its host is not loopback ' \
                      "(#{OT::Utils.redact_uri_userinfo(uri)}): the datastore password and data cross the " \
                      'network unencrypted. Use rediss:// and set VALKEY_REQUIRE_TLS=true to enforce it.'
        when :private_plaintext
          logger.info '[configure_familia] Redis/Valkey URI does not use TLS; its host is on a private network ' \
                      "(#{OT::Utils.redact_uri_userinfo(uri)}). Use rediss:// and set VALKEY_REQUIRE_TLS=true " \
                      'to require TLS.'
        end

        transport
      end

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

        raise Onetime::Problem, "Redis URI not configured (#{OT::Utils.redact_uri_userinfo(uri)})" if raise_error

        # Test environment safety: Ensure tests use port 2163
        # (boundary-anchored so e.g. :21630 doesn't pass)
        if ENV['RACK_ENV'] == 'test' && !uri.match?(%r{:2163(?:[/?]|\z)})
          raise Onetime::Problem, "Test environment MUST use Redis port 2163, got: #{OT::Utils.redact_uri_userinfo(uri)}. Set VALKEY_URL='valkey://127.0.0.1:2163/0'"
        end

        # Transport check (RISK-2026-08-14-L07): refuse a non-TLS URI when
        # redis.require_tls is set, else warn about plaintext to a remote
        # host. Before Familia.uri is assigned, so a refused boot leaves no
        # datastore configured.
        self.class.check_redis_transport!(
          uri, require_tls: self.class.redis_require_tls?(OT.conf.dig('redis', 'require_tls'))
        )

        # Set Familia's URI so it's available for isolated connections
        # during legacy data detection and other pre-connection operations
        Familia.uri = uri

        # Encryption keys with versioning for key rotation.
        #
        # v2: HKDF derivation (RFC 5869, used for new writes). The legacy v1
        #     unsalted-SHA-256 fallback was retired 2026-07-18.
        #
        # SECRET_PREVIOUS (C10 §3.3) registers previous SECRETs' derived keys
        # decrypt-only so old envelopes keep decrypting across a rotation;
        # see build_encryption_keys above. Familia expects base64-encoded
        # 32-byte keys.
        keys, current_version              = self.class.build_encryption_keys(
          secret_key, ENV.fetch('SECRET_PREVIOUS', nil)
        )
        Familia.config.encryption_keys     = keys
        Familia.config.current_key_version = current_version

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
        # under any prior (committed-fallback or empty) key still resolve.
        #
        # Verification-on-read (#3630): enabling verified_identifier? would reject
        # identifiers minted under prior keys. Requires upstream secret-history
        # mechanism (no familia support as of 2.12); re-minting is not viable since
        # existing links must keep resolving.
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
        # XChaCha20-Poly1305 (used once rbnacl/libsodium are present).
        # 'FamilialMatters' is Familia's long-standing default and the only
        # value compatible with any XChaCha20 data an installation may already
        # hold.
        #
        # It is ROTATABLE as of familia 2.12 (delano/familia#333): decrypt walks
        # the current value, then each encryption_personalization_history entry
        # in order, then the library default 'FamilialMatters' (always appended
        # automatically as the last candidate), trying each derived key until
        # Poly1305 auth succeeds. Encrypt is fail-closed and only ever uses the
        # current value.
        #
        # We intentionally leave the value at the library default in this
        # release and do NOT set the history knob (nothing to rotate from yet).
        # The per-deployment rotation is the v0.27.0 write-side flip (see
        # #3987), and it requires every process reading this datastore to be on
        # >= this release first -- a datastore-scoped invariant, not a
        # fleet-scoped one.
        Familia.config.encryption_personalization = 'FamilialMatters'

        # encryption_hkdf_salt feeds HKDF-SHA256 key derivation for
        # AES-256-GCM. All AES envelopes written by familia <= 2.10.x used the
        # then-hardcoded salt 'FamiliaEncryption'; familia >= 2.11 changes the
        # default to 'FamilialMatters' and only *falls back* to the legacy
        # value on decrypt. Pinning the legacy value keeps any AES writes
        # byte-compatible with existing data and with familia 2.10.x nodes
        # (mixed-version nodes on one datastore / rollback), and makes legacy
        # decrypts succeed on the first salt candidate instead of the
        # fallback. Rotating this later is supported via
        # encryption_hkdf_salt_history.
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

        OT.boot_logger.debug "[init] Configure Familia URI: #{OT::Utils.redact_uri_userinfo(uri)}"
      end
    end
  end
end
