# lib/onetime/session/surface.rb
#
# frozen_string_literal: true

module Onetime
  # Surface-bound sessions (#4409, epic #4408).
  #
  # `Onetime::Session` is the Rack session store CLASS, so this cannot nest
  # inside it; it takes the same sibling shape as {Onetime::SessionSidecar},
  # {Onetime::SessionImpersonation}, and {Onetime::SessionCodec}.
  #
  # A session's *surface* is the host classification under which its login
  # was completed. This module is the single source of truth for computing
  # a request's surface descriptor, stamping it on the session at login,
  # and answering "does this session belong on this request?".
  #
  # ## Surface descriptors
  #
  # The classifier returns one of four values; every consumer pattern-matches
  # on the `'kind'` key. Descriptors use strings because they are persisted
  # through the session JSON codec:
  #
  #     { 'kind' => 'canonical' }
  #     { 'kind' => 'subdomain', 'host' => 'eu.example.com' }
  #     { 'kind' => 'custom', 'id' => '<CustomDomain#identifier>' }
  #     nil     # unresolved, unverified, or a :custom whose id could not be read
  #
  # `:canonical` and `:subdomain` are distinct surface classes, not aliases.
  # A session established on the canonical host is not valid on a canonical
  # subdomain, and vice versa. Custom domains are keyed by
  # `CustomDomain#identifier` (the stable `objid`), not by display host, so
  # renaming a custom domain's display host does not invalidate the marker.
  #
  # ## Fail-closed handling
  #
  # `for_env` returns `nil` when the request's host is not one we serve, or
  # when a `:custom` strategy resolved to no identifier.
  #
  # `:invalid` is not only an unplaceable host. DomainStrategy also answers
  # it when its custom-domain lookup RAISES, so during a datastore blip a
  # real custom domain or platform subdomain arrives here as `:invalid` (see
  # the class doc of {Onetime::Middleware::DomainStrategy}). An `:invalid`
  # request is therefore classified again, with the same
  # {Onetime::Middleware::DomainStrategy::Chooserator.classify!} the
  # middleware uses, minus its rescue:
  #
  # - The lookup succeeds: the answer is exactly what a healthy request on
  #   that host would have carried. `nil` for a host we do not serve.
  # - The lookup fails again: the surface is UNKNOWN, which is not the same
  #   as wrong. `for_env` still answers `nil`, so every descriptor consumer
  #   (RecentReauth, ReauthPolicy via ReauthOffer, the WebAuthn surface_scope
  #   stamp, the OmniAuth Connect intent and callback) refuses as before.
  #   {match_status} answers `:unavailable`, which the session evaluators
  #   turn into a refusal that keeps the Rack session, the same treatment a
  #   customer-store outage gets. Destroying the session there would sign
  #   out every custom-domain and subdomain user for the length of the
  #   outage.
  #
  # The result is memoized on the env, so every consumer in one request
  # sees the same answer and the lookup runs once.
  #
  # A session with no stored marker (a session established before this
  # feature shipped, or one whose marker was cleared) is treated as
  # mismatched on every authenticated request. There is no "unknown ==
  # matches" branch: the epic's invariant requires an authoritative marker.
  module SessionSurface
    # Session data must remain stable across JSON persistence.
    KEY = 'authenticated_surface'

    CANONICAL = { 'kind' => 'canonical' }.freeze

    # Memo for the re-classification of an `:invalid` request.
    RECLASSIFIED_ENV_KEY = 'onetime.session_surface.reclassified'

    # Raised internally when re-classifying an `:invalid` request fails.
    # Never escapes this module.
    class Unavailable < StandardError; end
    private_constant :Unavailable

    class << self
      # Classify the request's surface from the Rack env populated by
      # DomainStrategy. Returns a frozen descriptor hash, or nil when the
      # request has no authoritative surface, including when it could not be
      # determined (see "Fail-closed handling" above).
      #
      # @param env [Hash] Rack env
      # @return [Hash, nil]
      def for_env(env)
        classify_request(env)
      rescue Unavailable
        nil
      end

      # Stamp the request's surface onto the session. Called from every
      # login-completion hook. A nil descriptor is stored as nil, which the
      # enforcement side treats as unauthenticated. That includes a surface
      # that could not be determined: the login does not stick, and the user
      # signs in again once the datastore answers. Fail closed.
      #
      # @param session [Hash] Rack session
      # @param env [Hash] Rack env
      # @return [Hash, nil] the stored descriptor
      def record(session, env)
        session[KEY] = for_env(env)
      end

      # Compares the session's stored surface with the current request's.
      #
      # - `:match` — both present and equal. Hash equality is deliberate:
      #   descriptors are frozen value objects, and two of them match iff
      #   every key does — the same rule for canonical (kind only),
      #   subdomain (kind + host), and custom (kind + id).
      # - `:mismatch` — no stored marker, a request we do not serve, or a
      #   different surface. Definitive: the session does not belong here.
      # - `:unavailable` — the session has a marker, but the request's
      #   surface could not be determined because the datastore failed.
      #
      # @param session [Hash] Rack session
      # @param env [Hash] Rack env
      # @return [Symbol] :match, :mismatch, or :unavailable
      def match_status(session, env)
        stored = session[KEY]
        return :mismatch if stored.nil?

        current = classify_request(env)
        return :mismatch if current.nil?

        stored == current ? :match : :mismatch
      rescue Unavailable
        :unavailable
      end

      # True only for a definite {match_status} of `:match`. Callers that
      # must not destroy a session over an outage use {match_status}.
      #
      # @param session [Hash] Rack session
      # @param env [Hash] Rack env
      # @return [Boolean]
      def matches_request?(session, env)
        match_status(session, env) == :match
      end

      # Read the stored descriptor without comparison. Callers that need to
      # log or surface the marker in diagnostics use this; enforcement uses
      # `matches_request?`.
      def recorded(session)
        session[KEY]
      end

      # Clear the marker. Called from logout and from any code path that
      # deliberately un-authenticates a session without destroying it.
      def clear(session)
        session.delete(KEY)
      end

      private

      # @raise [Unavailable] when an :invalid request cannot be re-classified
      def classify_request(env)
        return nil unless env.is_a?(Hash)

        strategy = env['onetime.domain_strategy']
        return reclassified(env) if strategy == :invalid

        descriptor(strategy, env['onetime.display_domain'], env['onetime.custom_domain_id'])
      end

      def descriptor(strategy, host, custom_domain_id)
        case strategy
        in :canonical
          CANONICAL
        in :subdomain
          host.to_s.empty? ? nil : { 'kind' => 'subdomain', 'host' => host }.freeze
        in :custom
          custom_domain_id.to_s.empty? ? nil : { 'kind' => 'custom', 'id' => custom_domain_id }.freeze
        else
          # nil or any future symbol we have not yet mapped.
          nil
        end
      end

      # The memo holds a descriptor, nil, or :unavailable.
      def reclassified(env)
        result = env.fetch(RECLASSIFIED_ENV_KEY) { env[RECLASSIFIED_ENV_KEY] = reclassify(env) }
        raise Unavailable if result == :unavailable

        result
      end

      def reclassify(env)
        host = env['onetime.display_domain'].to_s
        return nil if host.empty?
        # DomainStrategy puts the canonical host in display_domain when the
        # Host header is not a valid hostname, and the canonical host itself
        # classifies :canonical before any read. An :invalid request showing
        # the canonical host is therefore the substitute, not the real host.
        return nil if Onetime::Middleware::DomainStrategy.canonical_host?(host)

        # The same inputs the middleware instance passes (DomainStrategy#call).
        strategy       = Onetime::Middleware::DomainStrategy
        classification = strategy::Chooserator.classify!(
          host,
          strategy.canonical_domains_parsed || [],
          anchor_domains: strategy.anchor_domains_parsed || [],
        )
        descriptor(classification.strategy, host, classification.custom_domain&.identifier)
      rescue StandardError => ex
        Onetime.http_logger.error '[SessionSurface] Could not re-classify an :invalid request',
          { exception: ex, request_domain: host }
        :unavailable
      end
    end
  end
end
