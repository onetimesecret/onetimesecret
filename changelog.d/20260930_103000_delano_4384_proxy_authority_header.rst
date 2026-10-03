.. A new scriv changelog fragment.

Changed
-------

- The application now reads the host a visitor asked for from one forwarded
  header. ``Rack::DetectHost`` takes a single-valued ``X-Forwarded-Host`` from
  a trusted proxy, then ``Host``. ``Apx-Incoming-Host`` and
  ``X-Original-Host`` are no longer read, and a comma-separated
  ``X-Forwarded-Host`` is no longer read either: the request resolves on
  ``Host`` and a WARN names the header and the number of values. Discarding
  ``X-Forwarded-Host`` from a peer that is not a trusted proxy now logs at
  WARN. The admin host gate still compares the hosts named by the headers that
  are no longer read and returns 404 when one differs from the detected host.
  ``etc/examples/Caddyfile-example`` now overwrites ``X-Forwarded-Host`` and
  removes the other headers, with a commented block for translating
  ``Apx-Incoming-Host`` behind Approximated. The contract is described in
  ``docs/operations/proxy-authority-header.md``. (#4384)

  **Upgrade note for installs behind a Host-rewriting proxy**: if your proxy
  rewrites ``Host`` and forwards the public hostname only in
  ``Apx-Incoming-Host`` or ``X-Original-Host``, custom domains are served as
  the canonical site after upgrading. Change the proxy to send
  ``X-Forwarded-Host`` before you upgrade; the previous release already reads
  it.

  **Upgrade note for chained proxies**: a proxy that appends to an existing
  ``X-Forwarded-Host`` (Apache ``mod_proxy`` behind another proxy does)
  produces a comma-separated value. The first value used to be selected; now
  the request resolves on ``Host``. Have the proxy nearest the application
  overwrite the header with a single host, or preserve ``Host``.

- The colonel proxy diagnostic (``/api/colonel/system/proxy-headers``) no
  longer reports an application-side ``apx-incoming-host`` request header. The
  value the edge received is still reported. (#4384)
