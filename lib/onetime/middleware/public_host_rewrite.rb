# lib/onetime/middleware/public_host_rewrite.rb
#
# frozen_string_literal: true

require_relative 'strip_forwarded_host'

module Onetime
  module Middleware
    # PublicHostRewrite — set the Rack authority to the host the request was
    # classified on, so `Rack::Request#host` and the resolved env keys name
    # the same host (#4223).
    #
    # ## Why this exists
    #
    # Behind a proxy that rewrites `Host` to the origin target, the public
    # hostname arrives in `X-Forwarded-Host`. Rack::DetectHost reads it from a
    # trusted proxy and DomainStrategy classifies it into
    # `env['onetime.display_domain']` / `env['onetime.domain_strategy']`.
    # StripForwardedHost then removes the header, so `request.host` is the
    # origin target while the env keys name the public host. Code that reads
    # `request.host`, `request.base_url` or `HTTP_HOST` (mounted gems
    # included) gets the origin target.
    #
    # With `site.network.public_host_rewrite` on, this middleware writes the
    # classified host into `HTTP_HOST` and `SERVER_NAME`. The env that
    # reaches the apps is then the one a proxy that preserves `Host` would
    # have delivered for the same request.
    #
    # ## When a request is rewritten
    #
    # All of these hold:
    #
    #   - the setting is on (default off; off is a pass-through);
    #   - DomainStrategy classified the request :canonical, :subdomain or
    #     :custom. An :invalid request keeps its `Host` — that includes an
    #     unregistered host and a custom domain whose datastore read failed;
    #   - Rack::DetectHost published a host, it is a valid hostname, and it
    #     is the host DomainStrategy published as the display domain. When
    #     DomainStrategy substituted the canonical host for a request
    #     DetectHost did not accept, or when the domains feature is off and
    #     the display domain is `site.host` whatever the request named, the
    #     two differ and nothing is rewritten;
    #   - neither `X-Forwarded-Host` nor `Forwarded` is still in the env.
    #     Rack reads those ahead of `Host`, so a rewrite underneath them
    #     would not be what `request.host` returns. StripForwardedHost
    #     deletes both upstream; this is a check on the mount order;
    #   - `Host` does not already name that host. A `Host` Rack can parse
    #     whose hostname matches is left exactly as sent, port included.
    #
    # ## What is written
    #
    # `SERVER_NAME` is set to the hostname. `HTTP_HOST` also carries the
    # public port DetectHost validated for the selected, trusted
    # X-Forwarded-Host: the port in that header or, when it is a bare
    # hostname, the single-valued X-Forwarded-Port sent with it. The port is
    # left out when it is the default for the request's scheme, as a client
    # leaves it out of `Host`. No port is taken from the inbound `Host`: it
    # may belong to the origin hop or be unparseable (a doubled Host).
    #
    # Rack's #base_url reads the authority alone, while #port falls back to
    # X-Forwarded-Port when the authority has no port. Writing the port into
    # the authority and deleting `X-Forwarded-Port` keeps the two in
    # agreement on a rewritten request: the written authority is the only
    # port source left. Without the delete, #port would still read the header
    # whenever the authority carries no port — the scheme default was left
    # out, or X-Forwarded-Host named a port of its own and the header named
    # another. The header's name is added to
    # `env['onetime.stripped_forwarded_headers']`.
    # `SERVER_PORT` is left as the server set it: it is the listening port,
    # and Rack does not consult it for an http or https request with a Host.
    #
    # ## The original
    #
    # The `Host` the server received is kept in
    # `env['onetime.original_http_host']` on a rewritten request (absent
    # otherwise). Use .original_http_host to read it without caring whether a
    # rewrite happened.
    #
    # The raw `X-Forwarded-Host` is not kept. DetectHost publishes only its
    # validated authority when it selected that header and a valid port came
    # with it; StripForwardedHost still removes the raw header before apps
    # run.
    #
    # ## Ordering
    #
    # Mounted directly below DomainStrategy, which supplies the
    # classification. Everything above it has already run on the received
    # `Host`: DetectHost, AdminNetworkIsolation (its raw-`Host` comparison
    # is unaffected), StripForwardedHost, the session and identity
    # middleware. The env hash is shared, so those middlewares see the
    # rewritten value on the response path.
    class PublicHostRewrite
      # The `Host` header as received, set only on a rewritten request.
      ORIGINAL_HTTP_HOST = 'onetime.original_http_host'

      HTTP_HOST   = 'HTTP_HOST'
      SERVER_NAME = 'SERVER_NAME'

      # Classifications that name a host the install serves.
      REWRITE_STRATEGIES = %w[canonical subdomain custom].freeze

      # Carriers Rack reads ahead of `Host`.
      FORWARDED_CARRIERS = StripForwardedHost::STRIPPED_CANDIDATES

      # Rack reads it for #port when the authority carries none.
      X_FORWARDED_PORT = StripForwardedHost::X_FORWARDED_PORT
      STRIPPED_HEADERS = StripForwardedHost::STRIPPED_HEADERS

      # Read per request so the stack's shape does not depend on the setting.
      #
      # @return [Boolean]
      def self.enabled?
        OT.conf&.dig('site', 'network', 'public_host_rewrite') == true
      end

      # The `Host` header the server received, whether or not this
      # middleware rewrote it.
      #
      # @param env [Hash] Rack environment
      # @return [String, nil]
      def self.original_http_host(env)
        env.key?(ORIGINAL_HTTP_HOST) ? env[ORIGINAL_HTTP_HOST] : env[HTTP_HOST]
      end

      def initialize(app)
        @app = app
      end

      def call(env)
        host = self.class.enabled? ? rewrite_target(env) : nil
        rewrite(env, host) if host

        @app.call(env)
      end

      private

      # The host to write, or nil to leave the request as it is. See "When a
      # request is rewritten" above.
      def rewrite_target(env)
        return nil unless REWRITE_STRATEGIES.include?(env['onetime.domain_strategy'].to_s)
        return nil if FORWARDED_CARRIERS.any? { |key| env.key?(key) }

        detected = env[Rack::DetectHost.result_field_name].to_s
        return nil unless Onetime::Utils::DomainParser.basically_valid?(detected)
        return nil unless Onetime::Utils::DomainParser.hostname_matches?(env['onetime.display_domain'], detected)
        return nil if host_already?(env, detected)

        detected
      end

      # True when Rack parses the received authority and its hostname is
      # +host+. A doubled `Host` parses to no hostname and is not a match.
      def host_already?(env, host)
        Rack::Request.new(env).host.to_s.casecmp?(host)
      end

      def rewrite(env, host)
        port                    = public_port(env, host)
        env[ORIGINAL_HTTP_HOST] = env[HTTP_HOST]
        env[HTTP_HOST]          = port ? "#{host}:#{port}" : host
        env[SERVER_NAME]        = host
        strip_forwarded_port(env)
      end

      # See "What is written" above.
      def strip_forwarded_port(env)
        return unless env.key?(X_FORWARDED_PORT)

        env.delete(X_FORWARDED_PORT)
        env[STRIPPED_HEADERS] = (Array(env[STRIPPED_HEADERS]) + [X_FORWARDED_PORT]).freeze
      end

      # The port to write after +host+, or nil. DetectHost validated it for
      # this host on the trusted forwarded headers; the default port of the
      # request's scheme is not written.
      def public_port(env, host)
        authority = env[Rack::DetectHost.forwarded_authority_field_name]
        return nil unless authority && Onetime::Utils::DomainParser.hostname_matches?(authority, host)

        port = authority[/:(\d+)\z/, 1].to_i
        port unless port == Rack::Request::DEFAULT_PORTS[Rack::Request.new(env).scheme]
      end
    end
  end
end
