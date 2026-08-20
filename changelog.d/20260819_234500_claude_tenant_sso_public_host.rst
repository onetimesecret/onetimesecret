.. A new scriv changelog fragment.

Fixed
-----

- Fixed tenant SSO on custom domains behind a Host-rewriting proxy. Tenant
  resolution and the IdP redirect_uri now key on the public host rather than
  the request authority, which such a proxy replaces with the origin target.
  Not a regression — a sweep across every image from v0.25.11 to v0.26.5
  reproduces it identically; installs where it worked were relying on the edge
  sending ``X-Forwarded-Host``.

Security
--------

- The example Caddyfile no longer forwards a client-supplied
  ``X-Forwarded-Host``. It outranks ``Apx-Incoming-Host`` in host detection, so
  a visitor could shadow the hostname the ingress set and take a tenant's
  custom-domain surfaces down for the request.

Documentation
-------------

- Documented the host seam in the example Caddyfile: what changes for mounted
  gems when a proxy rewrites ``Host``, and why ``X-Forwarded-Host`` must be
  neither passed through nor pinned to ``{http.request.host}``.

AI Assistance
-------------

- Claude traced the split from production logs, implemented the public-host
  reads, and added ``scripts/host-seam/`` — a proxy-topology probe, a local
  Host-rewriting Caddy lane, and a release sweep across published images.
