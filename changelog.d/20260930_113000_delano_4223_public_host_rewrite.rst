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
