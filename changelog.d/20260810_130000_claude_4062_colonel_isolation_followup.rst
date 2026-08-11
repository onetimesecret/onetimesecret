.. A new scriv changelog fragment.

Added
-----

- **Operators:** a boot-time config check for ``ADMIN_ALLOWED_CIDRS``
  (``site.admin.allowed_cidrs``), beside the existing ``ADMIN_ALLOWED_HOSTS``
  check: a configured list where no entry parses as a CIDR is diagnosed at
  boot, in the startup log, rather than only when the first admin request
  meets the denying gate. The runtime posture is unchanged — a configured
  list with no usable range still denies both admin surfaces, and an empty or
  unset list still means "no network gate". (#4062)

Fixed
-----

- **Operators:** CIDR allowlist matching vs privacy masking. Client IPs are
  privacy-masked before middleware sees them (last IPv4 octet zeroed — an
  effective ``/24`` — and IPv6 to ``/48``), so ``ADMIN_ALLOWED_CIDRS`` entries
  narrower than the mask were accepted at boot, reported active, and then
  matched nothing. The network gate now answers allowlist membership against
  the true client IP through the verdict-only matcher the IP-privacy layer
  installs, so single-host entries (``/32``, ``/128``) match at full
  precision; the unmasked address still never lands in the request
  environment. Where the matcher is absent — a stack that never ran the
  privacy layer, so its addresses were never masked — the gate falls back to
  comparing the resolved address directly, fail-closed on a missing IP. (#4062)

- The frontend config contract now models ``site.admin.allowed_hosts``
  alongside ``allowed_cidrs`` (parity with ``config.defaults.yaml``); the
  schema previously stripped the key from parsed config. (#4062)

Changed
-------

- **Operators:** the admin-isolation denial WARNs name their remedy. Each of
  the four per-request refusals — allowlist miss, undetectable host,
  forwarded host from an untrusted peer, network isolation — logs a distinct
  message, and the boot diagnostics state what to set (a routable hostname,
  ``site.network.trusted_proxy``, or ``ADMIN_ALLOWED_HOSTS=*``) instead of
  only what was refused. (#4062)

Documentation
-------------

- **Operators:** corrected remedies in the admin-isolation guides. The
  trusted-proxy recipe now says to name the proxy's own address ranges in
  ``site.network.trusted_proxy.cidrs`` (``TRUSTED_PROXY_CIDRS``): filter mode
  with no explicit CIDRs trusts every private-network peer as a proxy, which
  restores exactly the forwarded-host spoofing the provenance rule exists to
  block. The "unset ``ADMIN_ALLOWED_HOSTS`` to allow the canonical host only"
  remedy is qualified: on a localhost or bare-IP install the canonical-anchor
  fallback has nothing to anchor on, so unsetting self-disables the host gate
  (boot WARN) rather than restricting it — not a hardening step there. New
  troubleshooting note for the most likely upgrade complaint: nginx's default
  ``proxy_pass`` rewrites ``Host`` to the upstream IP literal, so no host is
  detected and the gate 404s; forward the original host with
  ``proxy_set_header Host $host;``. (#4062)

AI Assistance
-------------

- Claude added the ``ADMIN_ALLOWED_CIDRS`` boot check and its spec, rewired
  the network gate onto the privacy layer's true-IP matcher with tryout
  coverage, added ``allowed_hosts`` to the frontend site-admin config
  contract and shape, reworked the trusted-proxy, unset-fallback and
  CIDR-precision guidance across
  ``docs/operations/admin-network-isolation.md``,
  ``docs/operations/colonel-admin-guide.md`` and ``.env.reference``, and
  wrote the nginx host-rewrite troubleshooting note. (#4062)
