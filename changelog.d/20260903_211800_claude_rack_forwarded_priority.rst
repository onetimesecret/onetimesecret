.. A new scriv changelog fragment.

Security
--------

- Rack no longer consults the RFC 7239 ``Forwarded`` header when resolving a
  request's host, port, scheme or client address. ``Rack::Request`` defaults
  to preferring ``Forwarded`` over the ``X-Forwarded-*`` family, but reverse
  proxies such as Caddy manage only the latter and pass an unmanaged
  ``Forwarded`` header through untouched, so a client could supply the
  authority that ``request.host`` resolved to. A boot initializer now pins
  ``Rack::Request.forwarded_priority`` to ``[:x_forwarded]`` process-wide,
  complementing the existing forwarded-host stripping middleware.

- Operators whose edge speaks only ``Forwarded`` (no ``X-Forwarded-Proto``)
  must emit the ``X-Forwarded-*`` family for TLS scheme detection. This is
  the Caddy default and the documented proxy configuration.
