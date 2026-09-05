# lib/onetime/initializers/configure_rack.rb
#
# frozen_string_literal: true

require 'rack/request'

module Onetime
  module Initializers
    # ConfigureRack initializer
    #
    # Sets process-wide Rack::Request policy so the RFC 7239 `Forwarded`
    # header is never consulted when Rack resolves a request's authority
    # (`Rack::Request#host`, `#port`), client address (`#ip` via
    # `#forwarded_for`) or scheme (`#scheme` via `#forwarded_scheme`).
    #
    # ## Why
    #
    # Rack 3.2's default `forwarded_priority` is `[:forwarded, :x_forwarded]`:
    # `Forwarded` WINS over the `X-Forwarded-*` family. Caddy (and most edges)
    # manage `X-Forwarded-Host` / `X-Forwarded-For` / `X-Forwarded-Proto` —
    # overwriting or stripping whatever the client sent — but pass an
    # unmanaged `Forwarded` header through untouched. That leaves a
    # discrepancy: the proxy's sanitized signal loses to the client's raw
    # one, and any `request.host` read resolves to an authority the client
    # chose. Pinning the priority to `[:x_forwarded]` closes that gap at the
    # Rack layer, independent of proxy configuration and of the middleware
    # stack (Onetime::Middleware::StripForwardedHost remains as the
    # belt-and-brace for `X-Forwarded-Host` and for any `Forwarded` host
    # parameter still in the env).
    #
    # ## Consequence for `Forwarded`-only proxies
    #
    # The priority applies to EVERY `forwarded_*` reader in Rack, not just
    # the authority. A proxy that speaks only RFC 7239 (no `X-Forwarded-Proto`,
    # no `X-Forwarded-For`) no longer contributes scheme or client IP through
    # Rack::Request. Scheme still resolves from `X-Forwarded-Proto` /
    # `X-Forwarded-Ssl` (see `Rack::Request.x_forwarded_proto_priority`) and
    # from the socket; client IP resolution for this app already goes through
    # Otto's IP privacy middleware, whose depth-mode `Forwarded` support is
    # configured separately (site.network.trusted_proxy.header) and reads the
    # env directly. Operators running a `Forwarded`-only edge must emit the
    # `X-Forwarded-*` family — the Caddy default — for TLS scheme detection.
    #
    # This is class-level state on Rack::Request (not runtime config), set
    # once per process and inherited by forked workers, so the initializer is
    # NOT fork-sensitive and has no cleanup.
    class ConfigureRack < Onetime::Boot::Initializer
      @provides = [:rack_request_policy]

      # Only the X-Forwarded-* family is trusted as a forwarding signal.
      FORWARDED_PRIORITY = [:x_forwarded].freeze

      def execute(_context)
        Rack::Request.forwarded_priority = FORWARDED_PRIORITY.dup

        OT.boot_logger.debug 'Configured Rack::Request.forwarded_priority',
          forwarded_priority: Rack::Request.forwarded_priority
      end
    end
  end
end
