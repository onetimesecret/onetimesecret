.. A new scriv changelog fragment.

Changed
-------

- **Operators — v0.26.5 upgrade note:** the Colonel admin surfaces
  (``/colonel`` and ``/api/colonel``) are host-gated in this release (#4062),
  and the gate judges the **validated detected host**, never a raw ``Host``
  header. Deployments behind a reverse proxy MUST forward the original Host
  header — nginx: ``proxy_set_header Host $host;`` (the default
  ``proxy_pass`` rewrites ``Host`` to the upstream IP literal, which is never
  detected as a host) — or both admin surfaces return 404 on **every**
  request after upgrade. This is fail-closed by design: admitting a request
  with no detectable host would let anyone who can reach the backend
  directly bypass the gate in exactly the topologies it protects. A proxy
  that forwards the public hostname in a forwarded header
  (``X-Forwarded-Host`` etc.) instead needs ``site.network.trusted_proxy``
  (``TRUSTED_PROXY_*``) configured with the proxy's own address ranges, or
  the forwarded host is refused. ``ADMIN_ALLOWED_HOSTS=*`` turns the host
  gate off deliberately and is the one-variable rollback. Each denial also
  logs a WARN naming the mechanism and the fix; see
  ``docs/operations/admin-network-isolation.md``. (#4127)

Added
-----

- **Operators:** a boot WARN when ``ADMIN_ALLOWED_HOSTS``
  (``site.admin.allowed_hosts``) is set but blank (``""`` or only
  whitespace/commas). Previously a written-but-empty allowlist was
  indistinguishable from unset: the host gate quietly fell back to the
  canonical anchors, and on a localhost or bare-IP install that fallback
  self-disables the gate entirely — the operator's written config produced
  no host gate with no boot-time signal. Runtime behavior is unchanged; the
  WARN names the fallback and every way out (a routable hostname, unsetting
  entirely, or ``*`` to disable the gate on purpose). (#4127)

AI Assistance
-------------

- Claude wrote the v0.26.5 reverse-proxy Host-forwarding upgrade callout,
  added the set-but-blank ``ADMIN_ALLOWED_HOSTS`` boot WARN with its spec
  coverage, and reworked the config template so an unset variable renders
  nil while a blank one renders an empty list — the distinction the new
  diagnostic depends on. Claude also restored the ``nullable`` wrapper the
  ``site.admin`` shape dropped, so the generated JSON Schema accepts the
  null that template now renders. (#4127)
