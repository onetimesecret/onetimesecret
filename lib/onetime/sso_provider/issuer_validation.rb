# lib/onetime/sso_provider/issuer_validation.rb
#
# frozen_string_literal: true

require 'json'
require_relative 'discovery_fetcher'
require_relative 'discovery_issuer'

module Onetime
  module SsoProvider
    # Process-wide verdicts on whether an INSTALL-WIDE OIDC issuer (OIDC_ISSUER)
    # matches the `issuer` its discovery document declares (#4513).
    #
    # WHY. The OIDC gem stack already refuses a mismatched issuer in the
    # request phase (OpenIDConnect::Discovery raises DiscoveryFailed), so the
    # browser never reaches the IdP. But the user sees the generic
    # `sso_failed`, the operator sees "Issuer mismatch" with neither value, and
    # the login page keeps advertising a provider that can never work. This
    # module records the verdict so the omniauth_setup hook can fail fast with
    # a specific error and AuthConfig#provider_active? can stop advertising the
    # provider.
    #
    # LAZY, NOT AT BOOT. The first sign-in attempt for the issuer performs the
    # check; nothing here runs at boot or in the background. Verdicts are
    # cached per process (Puma workers each learn independently):
    #
    #   :verified  exact match               cached VERIFIED_TTL (1 hour)
    #   :rejected  mismatch, missing issuer  cached REJECTED_TTL (2 minutes)
    #   :unknown   fetch failed / not JSON   cached UNKNOWN_TTL  (30 seconds)
    #
    # An :unknown verdict is NEVER treated as a mismatch: a timeout or an IdP
    # outage is not evidence of misconfiguration. The sign-in proceeds and the
    # gem's own discovery succeeds or fails exactly as it did before this
    # module existed. Caching :unknown briefly bounds the extra egress during an
    # outage to one probe per issuer per UNKNOWN_TTL instead of one per attempt.
    #
    # A rejection expires after REJECTED_TTL, so an operator who fixes the IdP
    # side (or the discovery document changes) recovers without a restart;
    # fixing OIDC_ISSUER itself needs a restart anyway, because strategies
    # register once at boot.
    #
    # Comparison is DiscoveryIssuer's exact String ==. No normalization.
    #
    # Thread safety: the verdict map is guarded by a Mutex. The fetch runs
    # OUTSIDE the lock so a slow IdP cannot serialize unrelated requests;
    # concurrent first requests may each probe once, and the last writer wins.
    module IssuerValidation
      VERIFIED_TTL = 3600
      REJECTED_TTL = 120
      UNKNOWN_TTL  = 30

      # Short timeouts: this runs inline in a user's sign-in request, ahead of
      # the gem's own discovery fetch.
      FETCH_OPEN_TIMEOUT = 3
      FETCH_READ_TIMEOUT = 3

      # Install-wide issuers number one or two per process; the cap only keeps
      # a misuse (arbitrary strings) from growing the map without bound.
      MAX_ENTRIES = 16

      STATES = [:verified, :rejected, :unknown].freeze

      UNPARSEABLE = Object.new.freeze
      private_constant :UNPARSEABLE

      # state:      :verified, :rejected or :unknown
      # detail:     DiscoveryIssuer reason (:match, :mismatch,
      #             :missing_discovered, :invalid_discovered) for
      #             verified/rejected; the DiscoveryFetcher status or
      #             :invalid_json for unknown
      # discovered: the discovered issuer String, or nil when absent/non-string
      # expires_at: monotonic clock deadline
      Verdict = Data.define(:state, :configured, :discovered, :detail, :expires_at) do
        def verified? = state == :verified
        def rejected? = state == :rejected
        def unknown?  = state == :unknown
      end

      @mutex    = Mutex.new
      @verdicts = {}

      class << self
        # Returns the cached verdict for +configured+, or probes discovery and
        # caches a fresh one. Never raises for network or document problems.
        #
        # @param configured [String] the install-wide issuer, verbatim
        # @param fetcher [#fetch] a DiscoveryFetcher (injectable for tests)
        # @return [Verdict]
        def verify(configured, fetcher: nil)
          cached = cached_verdict(configured)
          return cached if cached

          verdict = evaluate(configured, fetcher || default_fetcher)
          store(verdict)
          verdict
        end

        # Unexpired cached verdict, or nil. Performs no I/O, so it is safe on
        # hot per-request paths (AuthConfig#provider_active?).
        def cached_verdict(configured)
          now = monotonic_now
          @mutex.synchronize do
            verdict = @verdicts[configured]
            next nil unless verdict

            if verdict.expires_at <= now
              @verdicts.delete(configured)
              next nil
            end

            verdict
          end
        end

        # Whether a known, unexpired mismatch is cached for +configured+.
        # Unknown and absent verdicts answer false (fail open to the gem's own
        # check, never to an advertised-but-hidden state).
        def rejected?(configured)
          return false unless configured.is_a?(String) && !configured.empty?

          cached_verdict(configured)&.rejected? || false
        end

        # Test seam: forget every verdict.
        def reset!
          @mutex.synchronize { @verdicts.clear }
        end

        private

        def default_fetcher
          DiscoveryFetcher.new(open_timeout: FETCH_OPEN_TIMEOUT, read_timeout: FETCH_READ_TIMEOUT)
        end

        def evaluate(configured, fetcher)
          result = fetcher.fetch(DiscoveryFetcher.discovery_url_for(configured))
          return build(:unknown, configured, nil, result.status) unless result.ok?

          document = parse_document(result.body)
          return build(:unknown, configured, nil, :invalid_json) if document.equal?(UNPARSEABLE)

          check = DiscoveryIssuer.check_document(configured: configured, document: document)
          build(check.ok? ? :verified : :rejected, configured, check.discovered_string, check.reason)
        end

        # A body that is not JSON at all (an HTML maintenance page, a captive
        # portal) says nothing about the issuer, so it maps to :unknown. A
        # parsed non-Hash document flows on to DiscoveryIssuer, which rejects
        # it as :missing_discovered.
        def parse_document(body)
          JSON.parse(body.to_s)
        rescue JSON::ParserError
          UNPARSEABLE
        end

        def build(state, configured, discovered, detail)
          ttl = { verified: VERIFIED_TTL, rejected: REJECTED_TTL, unknown: UNKNOWN_TTL }.fetch(state)
          Verdict.new(
            state: state,
            configured: configured,
            discovered: discovered,
            detail: detail,
            expires_at: monotonic_now + ttl,
          )
        end

        def store(verdict)
          @mutex.synchronize do
            @verdicts.clear if @verdicts.size >= MAX_ENTRIES && !@verdicts.key?(verdict.configured)
            @verdicts[verdict.configured] = verdict
          end
        end

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
