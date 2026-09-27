---
id: "049"
status: accepted
title: "ADR-049: Use strict-origin for Referrer-Policy"
---

## Status

Accepted

## Date

2026-09-26

## Context

Secret URLs contain secret identifiers in their paths. The
[2026-08-02 security audit, finding M-3](../security/audit-2026-08-02/FINDINGS.md#m-3-http-security-headers-not-set-as-response-headers),
recommended an application-level `Referrer-Policy: no-referrer` header,
particularly for secret-reveal routes. OTS adopts the broader constraint that
no request initiated by an OTS document may disclose a URL path or query in a
`Referer` header, including on same-origin requests. This prevents secret URLs
from reaching application logs, error reports, or external services.

The initial remediation left two different policies in use. The document meta
tag and the Rack fallback for non-Otto responses used `no-referrer`, while Otto
versions before 2.12 emitted `strict-origin-when-cross-origin`. For navigations
started by a document, the document policy controlled the request.

SSO sign-in starts with a native form POST to `/auth/sso/:provider`. The form
must navigate the browser so it can follow the authentication redirect. Under
`no-referrer`, this request reached the application with `Origin: null`, and
`Rack::Protection::HttpOrigin` rejected it before the SSO flow began.

This behavior follows the
[WHATWG Fetch Standard, “append a request `Origin` header”](https://fetch.spec.whatwg.org/#append-a-request-origin-header)
(Living Standard updated 2026-09-21, retrieved 2026-09-26). For a non-CORS
request whose method is neither `GET` nor `HEAD`, the algorithm serializes the
origin as `null` when the referrer policy is `no-referrer`. For
`strict-origin`, it preserves the origin except on an HTTPS-to-HTTP downgrade.

The [W3C Referrer Policy specification](https://w3c.github.io/webappsec-referrer-policy/#referrer-policy-strict-origin)
(Editor's Draft dated 2026-03-20, retrieved 2026-09-26) defines
`strict-origin` to send only the source origin and to send no referrer on a
secure-to-insecure downgrade. By contrast, `same-origin` and
`strict-origin-when-cross-origin` can send the full URL on same-origin
requests. The standards define these behaviors but do not choose a policy for
OTS.

## Decision

The application Referrer-Policy is `strict-origin`.

Two constraints determine this choice:

1. **Never disclose a path or query in `Referer`.** This applies to
   same-origin and cross-origin requests. It rules out policies that can send a
   full URL, including `same-origin`, `strict-origin-when-cross-origin`,
   `origin-when-cross-origin`, `no-referrer-when-downgrade`, and `unsafe-url`.
2. **Preserve the origin on the same-origin HTTPS form POST that starts SSO.**
   This rules out `no-referrer`, which changes the request origin to the
   literal `null` for this navigation.

Both `origin` and `strict-origin` satisfy these constraints. `strict-origin` is
narrower because it also suppresses the referrer on an HTTPS-to-HTTP
downgrade.

We retain `Rack::Protection::HttpOrigin` on `/auth/sso/*`. Exempting the route
would weaken an Origin-based CSRF control to compensate for a header-policy
choice. Per [ADR-048](adr-048-evidence-basis-for-security-decisions.md),
`strict-origin` is an OTS judgment based on the documented constraints and the
normative browser behavior above.

## Trade-offs

- **We lose:** Compared with `no-referrer`, destinations learn the source
  origin except on a secure-to-insecure downgrade. On a custom domain, that
  origin includes the tenant hostname.
- **We gain:** Native SSO form POSTs retain the origin required by the CSRF
  check, while secret paths and queries remain absent from `Referer` headers.
- **Risk:** One application-wide value cannot satisfy a future page that must
  disclose no referrer information. Such a page would need a per-element or
  per-response override, and that override must not cover a page that starts a
  native form POST. Replacing the SSO initiation mechanism may remove this
  constraint and should trigger a review of this decision.

## Related

- [ADR-048: Evidence Basis for Security Decisions](adr-048-evidence-basis-for-security-decisions.md)
- [Security audit 2026-08-02, finding M-3](../security/audit-2026-08-02/FINDINGS.md#m-3-http-security-headers-not-set-as-response-headers)

## Implementation Notes

### Policy emission (2026-09-26)

[`Onetime::Middleware::Registry::REFERRER_POLICY`](../../lib/onetime/middleware/registry.rb)
is the source for HTTP response headers. The application base assigns it to
Otto routers, and `Rack::Protection::ReferrerPolicy` uses it as the fallback
for non-Otto responses. The Rack fallback is config-gated and enabled by
default; disabling `MIDDLEWARE_REFERRER_POLICY` removes that fallback without
changing Otto's policy.

The [`<meta name="referrer">`](../../apps/web/core/templates/partials/head-base.rue)
contains a literal `strict-origin` value because the template cannot read the
Ruby constant. Integration tests compare the literal with the constant and
verify the header on Otto responses. The
[SSO helper](../../src/shared/utils/sso.ts) uses the native form POST described
above.

### Edge overrides (2026-09-26)

The policy is one value at every layer OTS ships. The
[Caddy example](../../etc/examples/Caddyfile-example) sets the same
`strict-origin` header at the reverse proxy. Operator-deployed proxies and
CDNs are outside this repository; an override there is not covered by the
tests and operators must reconcile it with this decision. The
[Referrer Policy specification's delivery section](https://w3c.github.io/webappsec-referrer-policy/#referrer-policy-delivery)
has the `<meta name="referrer">` element set the document's policy after the
header, so for OTS documents a differing proxy header does not by itself change
the SSO form POST, but it does make the header and the document disagree.
