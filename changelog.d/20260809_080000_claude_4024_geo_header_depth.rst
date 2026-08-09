.. A new scriv changelog fragment.

Changed
-------

- **Operators:** ``GEO_HEADER`` (``site.network.geo.header``) is honored in
  ``TRUSTED_PROXY_MODE=filter`` only. otto 2.8 raises at configuration time
  when a geo header is set alongside ``trusted_proxy_depth``, so the
  YAML→otto translator applies the setting in filter mode and skips it under
  depth rather than failing the boot. This is not a new restriction in
  substance — depth mode never trusted geo headers, and the built-in vendor
  headers (``CF-IPCountry`` et al.) are equally inert there, so country has
  always resolved to otto's ``**`` unknown sentinel under depth. What
  changed is that otto now says so loudly instead of accepting the pairing
  silently. Depth-mode deployments that want real country data must use
  ``GEO_DB_PATH`` (a local MaxMind ``.mmdb``, looked up on the already-masked
  IP), which works in all modes. A ``GEO_HEADER`` set under depth now logs a
  startup warning naming the ignored value instead of being silently dropped,
  as does depth mode with no geo source at all (country resolves to ``**`` for
  every request). Both warn once per process rather than once per mounted
  application. (#4024, #4068)

- **Operators:** with ``TRUSTED_PROXY_MODE=depth``, configuring a depth is
  now itself the trust assertion. otto records
  ``otto.via_trusted_proxy = true`` from the connecting peer where it
  previously always reported ``false`` (delano/otto#226), so forwarded-host
  handling and ``X-Forwarded-Proto`` scheme authorization begin honoring
  forwarded headers in depth-mode deployments. That is the intended fix, but
  it means the origin must be unreachable except through the proxy tier: a
  client that can connect directly is now a trusted peer by configuration.
  (#4024)
