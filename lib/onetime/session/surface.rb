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
  #     nil     # :invalid, unresolved, or a :custom whose id could not be read
  #
  # `:canonical` and `:subdomain` are distinct surface classes, not aliases.
  # A session established on the canonical host is not valid on a canonical
  # subdomain, and vice versa. Custom domains are keyed by
  # `CustomDomain#identifier` (the stable `objid`), not by display host, so
  # renaming a custom domain's display host does not invalidate the marker.
  #
  # ## Fail-closed handling
  #
  # `for_env` returns `nil` when the request's domain_strategy is `:invalid`,
  # missing, or when a `:custom` strategy resolved to no identifier (blip in
  # the CustomDomain lookup). `matches_request?` treats a `nil` request
  # surface as mismatch — enforcement callers must refuse.
  #
  # A session with no stored marker (a session established before this
  # feature shipped, or one whose marker was cleared) is treated as
  # mismatched on every authenticated request. There is no "unknown ==
  # matches" branch: the epic's invariant requires an authoritative marker.
  module SessionSurface
    # Session data must remain stable across JSON persistence.
    KEY = 'authenticated_surface'

    CANONICAL = { 'kind' => 'canonical' }.freeze

    class << self
      # Classify the request's surface from the Rack env populated by
      # DomainStrategy. Returns a frozen descriptor hash, or nil when the
      # request has no authoritative surface.
      #
      # @param env [Hash] Rack env
      # @return [Hash, nil]
      def for_env(env)
        return nil unless env.is_a?(Hash)

        strategy = env['onetime.domain_strategy']
        case strategy
        in :canonical
          CANONICAL
        in :subdomain
          host = env['onetime.display_domain']
          host.to_s.empty? ? nil : { 'kind' => 'subdomain', 'host' => host }.freeze
        in :custom
          id = env['onetime.custom_domain_id']
          id.to_s.empty? ? nil : { 'kind' => 'custom', 'id' => id }.freeze
        else
          # :invalid, nil, or any future symbol we have not yet mapped.
          nil
        end
      end

      # Stamp the request's surface onto the session. Called from every
      # login-completion hook. A nil descriptor is stored as nil, which the
      # enforcement side treats as unauthenticated.
      #
      # @param session [Hash] Rack session
      # @param env [Hash] Rack env
      # @return [Hash, nil] the stored descriptor
      def record(session, env)
        session[KEY] = for_env(env)
      end

      # True when the session's stored surface descriptor equals the current
      # request's surface. Missing marker, mismatched marker, or an
      # unresolved request surface all return false. Hash equality is used
      # deliberately: descriptors are frozen value objects, and two of them
      # match iff every key does — the same rule for canonical (kind only),
      # subdomain (kind + host), and custom (kind + id).
      #
      # @param session [Hash] Rack session
      # @param env [Hash] Rack env
      # @return [Boolean]
      def matches_request?(session, env)
        stored  = session[KEY]
        current = for_env(env)
        return false if stored.nil? || current.nil?

        stored == current
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
    end
  end
end
