# lib/onetime/session/surface.rb
#
# frozen_string_literal: true

require_relative '../session'

module Onetime
  # Classifies request surfaces, stamps the login surface, and checks it on
  # later requests. Canonical and platform subdomains are distinct; custom
  # domains use the stable identifier, not the display hostname. Descriptors
  # use string keys for session JSON.
  #
  # An unresolved surface yields nil. A lookup outage is not a mismatch:
  # {match_status} returns `:unavailable` so callers refuse without destroying
  # the Rack session. Reclassification is memoized per request. A missing
  # stored marker is a mismatch, never a match.
  module Session::Surface
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

        # DomainStrategy published the lookup it made for this host (#4220),
        # which says which kind of :invalid this is without reading again: a
        # failed read is an outage, and an absent record means the middleware
        # classified a healthy answer, so the host is one we do not serve.
        published = env[Onetime::CustomDomain::Lookup::ENV_KEY]
        if published.is_a?(Onetime::CustomDomain::Lookup) && published.host == host
          raise published.error if published.read_failed?
          return nil if published.absent?
        end

        # Nothing published for this host (the env was not built by the
        # middleware): classify it again, without the middleware's rescue.
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
