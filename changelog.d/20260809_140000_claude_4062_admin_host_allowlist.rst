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
  ever match — ``=127.0.0.1``, ``=localhost``, ``=*.example.com``, or a
  non-ASCII name with no ``xn--`` form — leaves the host gate **active with an
  empty allowlist**: ``/colonel`` and ``/api/colonel`` return 404 on every
  hostname, and boot logs a WARN naming each rejected entry and why. Every one
  of those values is an operator writing an allowlist in order to restrict the
  admin surfaces, and the alternative — disabling the gate — would serve
  ``/colonel`` on every hostname the app answers on, the opposite of what was
  asked. The boot itself is not aborted: the admin surfaces are already
  fail-closed for this config, so stopping the process would take the public
  site, the API and the health endpoints down over an admin-console-only typo.
  Partial failures are unaffected: as long as one entry is enforceable the rest
  are dropped with a WARN. ``ADMIN_ALLOWED_HOSTS=*`` remains the way to ask for
  the gate to be off, and a ``*`` **anywhere** in the list is honoured — a
  sibling entry is ignored (and named in a WARN), never treated as ambiguous.
  (#4062)

- **Operators:** the admin host gate accepts a forwarded host header
  (``X-Forwarded-Host``, ``Apx-Incoming-Host``, ``X-Original-Host``,
  ``Forwarded``) **only** from a peer ``site.network.trusted_proxy`` vouched
  for. With no trusted proxy configured — the shipped default —
  ``Rack::DetectHost`` falls back to a heuristic that lets any peer on a
  private or loopback address name the host (#4024), which on a containerised
  install would let a request to a tenant custom domain claim to be the
  canonical admin host. When the gate refuses a forwarded host it returns the
  same 404; it deliberately does not fall back to the ``Host`` header, because
  in the ingress topology this defends ``Host`` carries the origin's own
  (allowlisted) hostname. **If both admin surfaces start 404ing after this
  upgrade** and your proxy forwards the public hostname in a header rather than
  rewriting ``Host``, configure ``site.network.trusted_proxy`` (correct for the
  CIDR gate, ban checks, sessions and audit attribution too) or set
  ``ADMIN_ALLOWED_HOSTS=*``. (#4062)

- **Operators:** an ``ADMIN_ALLOWED_CIDRS`` that is set but where **no** entry
  parses as a CIDR now denies both admin surfaces (logged at ERROR) instead of
  silently deactivating the network gate. Previously each malformed entry was
  warned away individually and the empty result read as "no network gate", so
  ``ADMIN_ALLOWED_CIDRS=100.64.0.0\10`` left the surfaces reachable from
  anywhere while the operator believed a VPN restriction was in force. An
  **empty or unset** list still means "no network gate" — that is the
  self-hosted default and is unchanged. (#4062)

- **Operators:** percent-encoded spellings of the admin paths (``/%63olonel``,
  ``/colonel%2Fsettings``) are gated exactly like ``/colonel``. The router
  decodes before dispatch, so matching the raw path would have let those
  spellings skip both gates and reach the admin console. (#4062)

- **Operators:** installs with no routable hostname are exempted rather than
  locked out. When ``ADMIN_ALLOWED_HOSTS`` is unset and neither canonical
  anchor is a hostname the app could ever detect — the shipped
  ``HOST=localhost:3000``, or an install reached by bare IP — the host gate
  self-disables and says so at WARN on boot. This exemption applies to the
  fallback only; a list the operator set is never silently disabled (above).
  (#4062)

- **Operators:** boot logs one INFO line per PROCESS, ``Admin surface isolation posture``,
  naming the effective hosts and CIDRs, whether each gate is active, and the
  ``site.network.trusted_proxy`` state (``disabled``, ``enabled
  (mode=filter)``, ``enabled (mode=depth)``). The trusted-proxy field is on
  that line because it qualifies the two beside it: with trusted proxy disabled
  — the shipped default — the detected host the gate judges may be chosen by
  any peer on a private or loopback address, and the client IP behind the CIDR
  gate comes from ``REMOTE_ADDR``. ``host_gate: active`` read next to
  ``trusted_proxy: disabled`` is the combination to look for. The line — and
  every admin-isolation boot WARN beside it — is emitted once per process, not
  once per mounted application. (#4062)

- **Operators:** ``AdminNetworkIsolation`` now mounts after ``Rack::DetectHost``
  — where the host it judges is produced — instead of ahead of it. One visible
  consequence: a request to ``/colonel`` while the app is still booting returns
  503 (startup readiness) rather than 404. (#4062)

AI Assistance
-------------

- Claude added the ``site.admin.allowed_hosts`` config key and its
  ``.env.reference`` entry, the shared ``Onetime::Utils::AdminHostAllowlist``
  classifier behind both the boot diagnostic and the gate, the host gate and
  mount-order move in ``Onetime::Middleware::AdminNetworkIsolation``, and the
  two-factor rewrite of ``docs/operations/admin-network-isolation.md``. (#4062)
