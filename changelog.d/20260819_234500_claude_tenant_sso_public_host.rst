.. A new scriv changelog fragment.

Fixed
-----

- Tenant SSO could not resolve a custom domain behind a Host-rewriting proxy.
  Approximated-style ingress puts the origin target in ``Host:`` and carries
  the visitor's hostname in ``Apx-Incoming-Host``; the omniauth setup hook
  keyed its ``CustomDomain`` lookup on Rack's ``request.host``, so the lookup
  missed and ``POST /auth/sso/<provider>`` answered ``302
  /signin?auth_error=sso_not_configured`` on a domain whose very same request
  classified as ``custom``. Tenant resolution, ``restrict_to`` enforcement and
  the callback's tenant validation now read the public host that
  ``Rack::DetectHost`` and ``DomainStrategy`` already resolved — the same
  source ``HttpOriginOptions``, ``Auth::SigninGate``, ``Auth::RestrictTo`` and
  the tenant CSP derivation read — so the runtime SSO gate and the display
  gates that decide whether to render the button cannot disagree about which
  tenant a request belongs to.

  This was never a regression: ``request.host`` has keyed that lookup since
  the hook was introduced, and a probe sweep across every published image from
  v0.25.11 through v0.26.5 reproduces the split identically in all of them.
  Deployments where tenant SSO worked were relying on the edge sending
  ``X-Forwarded-Host``, which Rack folds into ``request.host``.

Security
--------

- The example Caddyfile no longer forwards a client-supplied
  ``X-Forwarded-Host``. ``Rack::DetectHost`` ranks that header above
  ``Apx-Incoming-Host`` and accepts the first syntactically valid hostname
  without checking whether the domain is known, so a visitor could inject a
  header that outranks the one the ingress set: ``DomainStrategy`` then
  rejects the unknown domain, falls back to the canonical host, and that
  tenant's custom-domain surfaces — SSO included — stop resolving for the
  duration of the request. Nothing is lost by stripping it, because the same
  block pins ``X-Original-Host`` to Caddy's own view of the request and
  preserves ``Host``.

Documentation
-------------

- Documented the host seam in the example Caddyfile: what changes for the
  whole application, including mounted gems such as Rodauth, when a layer in
  front rewrites ``Host``, and why ``X-Forwarded-Host`` must be neither passed
  through from the client nor pinned to ``{http.request.host}`` — pinning
  masks ``Apx-Incoming-Host`` and produces the same failure by a different
  route.

AI Assistance
-------------

- Claude traced the split from production logs, added the public-host
  accessor and routed every tenant-keyed read and log through it, and wrote
  the unit and full-stack specs — the integration spec drives the
  Approximated topology (``Host:`` origin target plus ``Apx-Incoming-Host:``
  tenant domain), the lane no spec previously covered, which is why this
  shipped. Also contributed ``scripts/host-seam/``: a topology probe that
  compares the ``O-Domain-Strategy`` oracle against the SSO POST's
  ``Location`` across eleven proxy shapes, a Caddy lane that reproduces
  Host-rewriting ingress locally (local development is otherwise structurally
  blind to this class, since a plain ``reverse_proxy`` preserves ``Host``),
  and a release sweep that runs the matrix against published images.
