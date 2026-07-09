# lib/onetime/security/request_context.rb
#
# frozen_string_literal: true

require 'otto'

module Onetime
  module Security
    # Privacy-safe capture of per-request network context for the secret
    # activity audit pipeline (#3640).
    #
    # ---------------------------------------------------------------------------
    # PRIVACY STANCE (authoritative decision: ADR-022)
    # ---------------------------------------------------------------------------
    # The org audit trail records only a REDUCED, non-reversible view of the
    # caller's network identity -- never the raw values:
    #
    #   net_ip_partial : IPv4 with the last octet zeroed (IPv6 last 80 bits),
    #                    a balance of forensic value and personal privacy.
    #   net_ua_partial : user agent with version/build identifiers stripped and
    #                    the remainder truncated.
    #   net_ip_hash    : keyed HMAC-SHA256 over the PARTIAL IP -- an opaque,
    #                    stable correlation token (correlation without
    #                    disclosure), matching the trail's "shortids only, no
    #                    capability tokens" posture.
    #
    # The raw dotted-quad IP and the full User-Agent string are NEVER stored,
    # anywhere in this pipeline.
    #
    # Two deliberate properties:
    #
    # 1. Hash the PARTIAL, not the raw. The keyed hash is computed over the
    #    already-masked IP, so it can never encode anything finer than the /24
    #    we are willing to store. Correlation is therefore at /24 granularity.
    #    This is the most conservative posture: the raw IP is handled by exactly
    #    one operation (mask_ip) and reduced immediately; it never flows into a
    #    second code path.
    #
    # 2. Defense in depth. Otto's IPPrivacyMiddleware already masks REMOTE_ADDR /
    #    otto.client_ip and scrubs the User-Agent at the edge, so the values that
    #    reach this layer are typically already reduced. This helper re-applies
    #    the reduction UNCONDITIONALLY and idempotently, so even if that
    #    middleware is ever disabled or a future change routes a raw value here,
    #    the stored attributes stay masked. Masking an already-masked IP is a
    #    no-op; stripping versions from an already-stripped UA is a no-op.
    #
    # Layer-agnostic: no Rack dependency. Callers pass plain ip / user_agent
    # strings (e.g. read from the auth StrategyResult metadata), so this is
    # equally usable from request handlers, jobs, or specs.
    module RequestContext
      extend self

      # String keys so they splat cleanly through the model layer's **event_attrs
      # (see Receipt#record_org_audit_event) and JSON round-trip in the trail.
      NET_IP_PARTIAL = 'net_ip_partial'
      NET_UA_PARTIAL = 'net_ua_partial'
      NET_IP_HASH    = 'net_ip_hash'

      # Trailing octets to zero when masking an IP (1 => last IPv4 octet).
      IP_MASK_OCTETS = 1

      # Upper bound on the stored partial user agent. Well under Otto's own 500
      # so the stored value is unambiguously a truncated partial.
      UA_MAX_LENGTH = 200

      # Build the string-keyed network-context attributes for an audit event.
      #
      # Every key is present only when its value could be derived, so a request
      # with no network context (e.g. an internal caller with no ip/ua) yields
      # an empty hash and records the event with no network attributes rather
      # than nils.
      #
      # @param ip [String, nil] client IP as seen at the calling layer (already
      #   edge-masked in production; re-masked here defensively).
      # @param user_agent [String, nil] client User-Agent header value.
      # @param key [String, nil] HMAC key for the correlation hash. Defaults to
      #   the app's server secret; when blank the hash is omitted rather than
      #   computed under a weak key.
      # @return [Hash{String=>String}] masked/partial/hashed attributes only.
      def capture(ip:, user_agent:, key: default_key)
        attrs = {}

        partial_ip = mask_ip(ip)
        if partial_ip
          attrs[NET_IP_PARTIAL] = partial_ip
          correlation           = hash_ip(partial_ip, key)
          attrs[NET_IP_HASH]    = correlation if correlation
        end

        partial_ua            = mask_user_agent(user_agent)
        attrs[NET_UA_PARTIAL] = partial_ua if partial_ua

        attrs
      end

      # The server-side secret used to key the correlation hash.
      #
      # This is the application's global secret (== site.secret), already the
      # root the app uses for keyed digests (see Onetime::KeyDerivation and the
      # IncomingConfig recipient hashing). It is stable across requests, so the
      # same partial IP always yields the same hash (correlatable), while the
      # hash stays non-reversible without the secret. We deliberately do NOT use
      # Otto's daily-rotating hash key, whose rotation would break long-horizon
      # correlation in the trail.
      #
      # @return [String, nil]
      def default_key
        OT.global_secret
      end

      # Zero the last IPv4 octet (or last 80 IPv6 bits) via Otto's masking
      # helper. Idempotent on an already-masked address. Returns nil for blank
      # or malformed input so a bad value can never fall through as a raw string.
      #
      # @param ip [String, nil]
      # @return [String, nil] masked IP, or nil.
      def mask_ip(ip)
        return nil if ip.to_s.strip.empty?

        Otto::Privacy::IPPrivacy.mask_ip(ip.to_s, IP_MASK_OCTETS)
      rescue ArgumentError
        # Not a parseable IP -- drop it rather than store an un-masked token.
        nil
      end

      # Keyed HMAC-SHA256 correlation hash over the (already partial) IP.
      #
      # @param partial_ip [String, nil] the masked IP.
      # @param key [String, nil] HMAC key (the server secret).
      # @return [String, nil] 64-char hex digest, or nil when ip/key is blank.
      def hash_ip(partial_ip, key)
        return nil if partial_ip.to_s.strip.empty? || key.to_s.empty?

        Otto::Privacy::IPPrivacy.hash_ip(partial_ip.to_s, key.to_s)
      rescue ArgumentError
        nil
      end

      # Strip version and build identifiers, then truncate.
      #
      # Mirrors Otto::Privacy::RedactedFingerprint#anonymize_user_agent (a
      # private instance method, so we cannot call it directly) so a UA reduced
      # at the edge and one reduced here agree. Idempotent: re-stripping an
      # already-stripped UA changes nothing.
      #
      # @param ua [String, nil]
      # @return [String, nil] the partial UA, or nil for blank input.
      def mask_user_agent(ua)
        return nil if ua.to_s.strip.empty?

        # Build identifiers first (must precede version stripping, else the
        # asterisks it inserts break the version regex -- see Otto's note).
        reduced = ua.to_s.gsub(%r{Build/[\w.-]+}, 'Build/*')

        # Version patterns (longest first), dot- or underscore-separated.
        reduced = reduced
          .gsub(/\d+[._]\d+[._]\d+[._]\d+/, '*.*.*.*')
          .gsub(/\d+[._]\d+[._]\d+/, '*.*.*')
          .gsub(/\d+[._]\d+/, '*.*')

        reduced.length > UA_MAX_LENGTH ? reduced[0, UA_MAX_LENGTH] : reduced
      end
    end
  end
end
