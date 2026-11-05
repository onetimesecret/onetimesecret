.. A new scriv changelog fragment.

Security
--------

- Upgraded otto to 2.13. With ``site.network.trusted_proxy`` in ``filter``
  mode, the client IP is now read from ``X-Forwarded-For`` from the right,
  skipping trusted hops and stopping at the first entry that is not one, so a
  client-supplied leftmost entry is never selected even when the proxy
  appends. Before, the leftmost untrusted entry won, which the client controls
  when the proxy appends, so IP rate limits, bans and the admin network gate
  could be steered by a forged header unless the edge overwrote it.
  **Behavior change for operators**: every proxy between the client and the
  application must now be in the trusted set. Private, loopback and link-local
  hops always are; a CDN edge or load balancer with a public address must be
  listed in ``trusted_proxy.cidrs`` (``TRUSTED_PROXY_CIDRS``), or that hop
  becomes the client IP for every request through it. A proxy that writes
  ``unknown`` or an empty entry where the client address belongs now leaves
  the request with no client IP (it used to resolve to the proxy's own
  address): the per-IP rate limiters skip such requests and the admin network
  gate denies them. ``X-Real-IP`` and ``X-Client-IP`` are read only when
  ``X-Forwarded-For`` is absent. See ``docs/deployment/trusted-proxies.md``,
  "Client IP resolution". (delano/otto#292)

- The auth-strategy and admin-gate client IP fallbacks no longer re-resolve
  from ``REMOTE_ADDR`` when the IP privacy middleware ran and found no client
  IP, which would have attributed the request to the proxy, unmasked.

Fixed
-----

- ``HEAD`` requests to the Otto-routed applications return the matching
  ``GET`` route's status and headers with an empty body, and no longer fail
  once the configuration is frozen after the first request. (delano/otto#294)

Changed
-------

- Vendor client-address headers (``CF-Connecting-IP``, ``True-Client-IP``,
  ``Fly-Client-IP`` and others) are rewritten to the masked client IP along
  with ``X-Forwarded-For`` when IP privacy is on. They were never read for
  the client IP; they now no longer carry the raw address into the request
  environment either. (delano/otto#292)
