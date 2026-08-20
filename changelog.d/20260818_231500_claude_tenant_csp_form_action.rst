.. A new scriv changelog fragment.

Fixed
-----

- Tenant SSO on a custom domain was blocked by the site's own
  Content-Security-Policy in Chromium. The ``form-action`` allowlist was
  assembled once at boot from process-global environment variables, so IdP
  origins stored in per-domain ``CustomDomain::SsoConfig`` records never
  reached the header. The SSO form POST answers with a 302 to the IdP, and
  Chromium enforces ``form-action`` across the whole redirect chain, so the
  hop was refused — with no server-side error, only a browser-console
  message. Firefox checks only the initial same-origin form target and never
  tripped, which is why the failure looked browser-specific. Tenant IdP
  origins are now derived per-request from the resolved display domain and
  folded into ``form-action`` additively.

Changed
-------

- ``SSO_FORM_ACTION_ORIGINS`` is re-scoped. It is no longer the way to admit
  a tenant's IdP on a custom domain — that is now automatic — and is reserved
  for split-endpoint OIDC topologies where the authorization endpoint lives on
  an origin the issuer does not name, plus the tenant derivation gap when a
  domain record cannot be read at response time. The boot warning for
  "override set with no active platform providers" is reworded from a config
  smell to informational, because that combination is now a legitimate
  split-endpoint configuration.

- Development-mode CSP shape follows otto's own policy again. otto 2.8.1+
  leads its development ``script-src`` with ``'self'``, which made the
  app-side shim that appended it unreachable; the shim is removed and the
  development policy is pinned to an exact token sequence in spec, so a
  future otto change to that security header surfaces in review rather than
  silently.

Documentation
-------------

- Corrected the sovereign-cloud Entra guidance for both SSO surfaces. The
  previous advice — add the sovereign login origin to
  ``SSO_FORM_ACTION_ORIGINS`` — could not work on either: neither the tenant
  nor the platform Entra strategy passes an authority option, so both always
  redirect to the commercial cloud and the override widened the policy on
  every page for every tenant while fixing nothing. Sovereign deployments
  configure provider type ``oidc`` with the sovereign v2.0 issuer, which the
  boot-time (platform) and per-request (tenant) derivations handle on their
  own. Documented the sovereign issuer values, the v1-issuer split-endpoint
  trap, the ``allowed_domains`` access-control posture, and the identity
  re-link cost of switching an existing configuration from ``entra_id``.

AI Assistance
-------------

- Claude implemented the per-request derivation: a Core middleware that
  resolves the display domain to its ``SsoConfig`` on HTML responses and
  writes the validated IdP origin into otto 2.9.0's opt-in request-scoped CSP
  extras channel, an origin-validation funnel on ``AuthConfig`` that treats
  tenant-supplied issuers as attacker-influenced input, and the spec coverage
  pinning the additive merge, the sanitization refusals, and the fail-closed
  degradation to pre-fix behavior.
