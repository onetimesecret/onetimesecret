.. A new scriv changelog fragment.

Fixed
-----

- Behind a trusted proxy, the IP-privacy middleware now masks the real client
  IP instead of the proxy's. The middleware was mounted first in the common
  stack with no security config, so it resolved ``REMOTE_ADDR`` (ignoring
  ``X-Forwarded-For``) and overwrote the forwarded headers with a masked proxy
  address before any later strategy could read the client IP — the
  ``site.network.trusted_proxy`` setting from #3116 ran too late to help. The
  middleware stack now passes it an Otto security config that trusts the
  private proxy ranges (RFC1918, loopback, link-local, IPv6 ULA/loopback) when
  ``site.network.trusted_proxy.enabled`` is true. Direct-connection
  deployments are unaffected; the stored IP is still masked to a /24, just the
  correct one. Public-egress CDN ranges still need CIDR matching, which Otto's
  prefix-based trusted-proxy list does not do. (#3427)

Added
-----

- ``scripts/ip_privacy_trusted_proxy_repro.rb``, a standalone diagnostic that
  models the chained ``IPPrivacyMiddleware`` instances and prints the broken
  vs. fixed behaviour, kept for the trusted-proxy harmonization follow-up.
  (#3427)
