.. A new scriv changelog fragment.

Added
-----

- **Operators:** ``ADMIN_ALLOWED_HOSTS`` (``site.admin.allowed_hosts``) — a
  comma-separated list of hostnames that serve the Colonel admin surfaces
  (``/colonel`` and ``/api/colonel``). A request whose validated detected host
  is not on the list receives the same 404 the existing CIDR allowlist returns:
  indistinguishable from an absent route, never a 403. Host and network are
  independent factors and a request must pass every gate that is active;
  neither replaces the other, and both sit on top of the two app-layer auth
  layers, which still enforce beneath them. Entries are matched literally
  (no ``www.`` synthesis, no patterns) and must be ASCII A-labels, so an
  internationalized domain has to be given in its ``xn--`` punycode form.
  (#4062)

Changed
-------

- **Operators:** the admin host gate is **active without configuration**.
  Unset or empty, it falls back to the deployment's canonical anchor hosts —
  ``features.domains.default`` (``DEFAULT_DOMAIN``) and ``site.host``
  (``HOST``) — plus their ``www.`` siblings. A stock canonical install is
  unchanged, while tenant custom domains and ``LINK_DOMAINS`` link-pool hosts
  stop serving the admin console. If you reach ``/colonel`` on any other
  hostname, set ``ADMIN_ALLOWED_HOSTS`` to that hostname before upgrading or it
  will 404. Rollback is one variable: ``ADMIN_ALLOWED_HOSTS=*`` as the sole
  entry disables the host gate (logged at WARN on boot) and leaves the CIDR
  gate untouched. (#4062)

- **Operators:** an ``ADMIN_ALLOWED_HOSTS`` that names nothing the gate could
  ever match **fails the boot**, naming each rejected entry and why —
  ``ADMIN_ALLOWED_HOSTS=127.0.0.1``, ``=localhost``, ``=*.example.com``, or a
  non-ASCII name with no ``xn--`` form. Every one of those is an operator
  writing an allowlist in order to restrict the admin surfaces, and the
  alternative — disabling the gate — would serve ``/colonel`` on every hostname
  the app answers on, the opposite of what was asked. Partial failures still
  boot: as long as one entry is enforceable the rest are dropped with a WARN.
  ``ADMIN_ALLOWED_HOSTS=*`` remains the way to ask for the gate to be off.
  (#4062)

- **Operators:** installs with no routable hostname are exempted rather than
  locked out. When ``ADMIN_ALLOWED_HOSTS`` is unset and neither canonical
  anchor is a hostname the app could ever detect — the shipped
  ``HOST=localhost:3000``, or an install reached by bare IP — the host gate
  self-disables and says so at WARN on boot. This exemption applies to the
  fallback only; a list the operator set is never silently disabled (above).
  (#4062)

- **Operators:** boot logs one INFO line, ``Admin surface isolation posture``,
  naming the effective hosts and CIDRs, whether each gate is active, and the
  ``site.network.trusted_proxy`` state (``disabled``, ``enabled
  (mode=filter)``, ``enabled (mode=depth)``). The trusted-proxy field is on
  that line because it qualifies the two beside it: with trusted proxy disabled
  — the shipped default — the detected host the gate judges may be chosen by
  any peer on a private or loopback address, and the client IP behind the CIDR
  gate comes from ``REMOTE_ADDR``. ``host_gate: active`` read next to
  ``trusted_proxy: disabled`` is the combination to look for. (#4062)

- **Operators:** ``AdminNetworkIsolation`` now mounts after ``Rack::DetectHost``
  — where the host it judges is produced — instead of ahead of it. One visible
  consequence: a request to ``/colonel`` while the app is still booting returns
  503 (startup readiness) rather than 404. (#4062)

AI Assistance
-------------

- Claude added the ``site.admin.allowed_hosts`` config key and its
  ``.env.reference`` entry, the shared ``Onetime::Utils::AdminHostAllowlist``
  classifier behind both the boot validation and the gate, the host gate and
  mount-order move in ``Onetime::Middleware::AdminNetworkIsolation``, and the
  two-factor rewrite of ``docs/operations/admin-network-isolation.md``. (#4062)
