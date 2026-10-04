.. A new scriv changelog fragment.

Added
-----

- ``site.network.public_host_rewrite`` (``PUBLIC_HOST_REWRITE``), off by
  default. It is for installs behind a proxy that rewrites ``Host`` to the
  origin target and sends the public hostname in ``X-Forwarded-Host``. When
  on, a request that classified as a canonical host, a subdomain of one, or a
  registered custom domain has ``Host`` set to the detected hostname before
  the mounted applications run, so code that reads the Rack request host
  directly sees the same host as the rest of the application. Requests that
  do not classify, and requests whose ``Host`` already names that host, are
  left as received. The ``Host`` as received is kept in the Rack env as
  ``onetime.original_http_host``, and the colonel proxy diagnostic reports it
  as ``request_headers.host``. With the setting off nothing changes. See
  ``docs/operations/proxy-authority-header.md``. (#4223)

Changed
-------

- ``X-Forwarded-Port`` is read only from a trusted proxy, on the same verdict
  as ``X-Forwarded-Host``, and only when it is one port from 1 through 65535.
  Otherwise it is removed before the applications run. The example Caddyfile
  and the nginx snippet in ``docs/operations/proxy-authority-header.md`` now
  remove the header at the proxy; a proxy that passes a client's value through
  lets the client choose the port in generated URLs. (#4223)

- ``X-Forwarded-Proto``, ``X-Forwarded-Scheme`` and ``X-Forwarded-SSL`` are
  read only from a trusted proxy, on the same verdict as ``X-Forwarded-Host``:
  the peer passed ``site.network.trusted_proxy`` when that is configured, or
  connects from a private or loopback address when it is not. From any other
  peer they are removed, so the request has the scheme of the connection to
  the origin. This applies whether or not ``public_host_rewrite`` is on.
  **Check before upgrading**: an install whose TLS-terminating proxy or CDN
  connects to the origin from a public address, without
  ``site.network.trusted_proxy`` naming it, is seen as ``http`` after the
  upgrade. A ``Secure`` session cookie is then not written (sign-in fails) and
  request-derived URLs such as an SSO ``redirect_uri`` use ``http``. Add the
  proxy's address ranges to ``site.network.trusted_proxy``, or set
  ``ASSUME_HTTPS=true``. The ``[Session] cookie NOT written`` warning now
  lists the removed headers under ``untrusted_scheme_headers``. (#4223)

- A trusted proxy's ``X-Forwarded-Proto`` or ``X-Forwarded-Scheme`` of ``wss``
  is read as ``https``, and ``ws`` as ``http``; so is the ``proto=`` of
  ``Forwarded`` when that family is the one read. Rack accepts both values and
  has no default port for either, so a request forwarded as ``wss`` with no
  public port had the origin hop's port as its request port and ``wss://`` in
  request-derived URLs. This applies whether or not ``public_host_rewrite`` is
  on. (#4223)
