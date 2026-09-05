.. A new scriv changelog fragment.

Security
--------

- Rack no longer consults the RFC 7239 ``Forwarded`` header when resolving a
  request's host, port, scheme or client address unless the proxy
  configuration names it. ``Rack::Request`` defaults to preferring
  ``Forwarded`` over the ``X-Forwarded-*`` family, but reverse proxies such
  as Caddy manage only the latter and pass an unmanaged ``Forwarded`` header
  through untouched, so a client could supply the authority that
  ``request.host`` resolved to. The app now pins
  ``Rack::Request.forwarded_priority`` (via otto 2.10's
  ``trusted_proxy_header``) to ``[:x_forwarded]`` on every deployment,
  including ones with proxy trust disabled, complementing the existing
  forwarded-host stripping middleware. Depth mode with
  ``site.network.trusted_proxy.header: Forwarded`` pins ``[:forwarded]``
  instead.

- Operators whose edge speaks only ``Forwarded`` (no ``X-Forwarded-Proto``)
  must either emit the ``X-Forwarded-*`` family for TLS scheme detection or
  run ``trusted_proxy.mode: depth`` with ``header: Forwarded``. Emitting
  ``X-Forwarded-*`` is the Caddy default and the documented proxy
  configuration.
