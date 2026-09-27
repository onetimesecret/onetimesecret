---
id: "049"
status: proposed
title: "ADR-049: Referrer-Policy is strict-origin"
---

## Status

Proposed

## Date

2026-09-26

## Context

Secret links carry the secret identifier in the URL path. The 2026-08-02
security audit (item M-3.2) requires that the path and query of a secret URL
never reach a `Referer` header, on same-origin navigations included, because
a `Referer` lands in access logs, error reports, and third-party servers.

Before this decision the application emitted `Referrer-Policy: no-referrer`
and repeated it in the document's `<meta name="referrer">`. That value
satisfies M-3.2 but breaks SSO sign-in. The browser derives the `Origin`
header of a non-CORS POST from the referrer policy. The WHATWG Fetch Standard,
section 3.1 "`Origin` header", algorithm "append a request `Origin` header"
(living standard, retrieved 2026-09-26,
<https://fetch.spec.whatwg.org/#append-a-request-origin-header>), reads:

> Otherwise, if request's method is neither `GET` nor `HEAD`, then:
> If request's mode is not "cors", then switch on request's referrer policy:
> "no-referrer": Set serializedOrigin to `null`.
> "no-referrer-when-downgrade", "strict-origin", "strict-origin-when-cross-origin":
> If request's origin is a tuple origin, its scheme is "https", and request's
> current URL's scheme is not "https", then set serializedOrigin to `null`.
> "same-origin": If request's origin is not same origin with request's current
> URL's origin, then set serializedOrigin to `null`.

SSO sign-in starts with a native HTML form POST to `/auth/sso/:provider`
(`src/shared/utils/sso.ts`), because the endpoint answers with a redirect to
the identity provider that an XHR cannot follow. A form submission is a
non-CORS POST, so under `no-referrer` it arrives as `Origin: null`.
`Rack::Protection::HttpOrigin` refuses a literal `null` Origin, as it should,
and the sign-in fails. Every other state-changing request in the SPA goes
through `fetch()`, whose default mode is `cors` and always carries the real
Origin, which is why the defect only surfaced when the tenant SSO end-to-end
test drove the form POST on a custom domain (#4542).

External recommendations disagree with each other, so none of them settles
the choice on its own:

- The OWASP HTTP Headers Cheat Sheet
  (<https://cheatsheetseries.owasp.org/cheatsheets/HTTP_Headers_Cheat_Sheet.html>,
  retrieved 2026-09-26) recommends `Referrer-Policy: strict-origin-when-cross-origin`:
  "Today, the default behavior in modern browsers is to no longer send all
  referrer information (origin, path, and query string) to the same site but
  to only send the origin to other sites."
- The OWASP Secure Headers Project's best-practice configuration
  (`ci/headers_add.json`, retrieved 2026-09-26) recommends
  `Referrer-Policy: no-referrer`, the value that failed here.
- Browsers default to `strict-origin-when-cross-origin` when no policy is set
  (MDN, Referrer-Policy reference, retrieved 2026-09-26).

The W3C Referrer Policy specification (Editor's Draft,
<https://w3c.github.io/webappsec-referrer-policy/>, retrieved 2026-09-26)
defines the candidate values:

> The `strict-origin` policy sends the ASCII serialization of the origin of
> the referrerURL for requests whose referrerURL and current URL are both
> potentially trustworthy URLs, or whose referrerURL is a non-potentially
> trustworthy URL.

> The `strict-origin-when-cross-origin` policy specifies that a request's
> full referrerURL is sent as referrer information when making
> same-origin-referrer requests, and only the ASCII serialization of the
> origin of the request's referrerURL is sent when making
> cross-origin-referrer requests.

> The `same-origin` policy specifies that a request's full referrerURL is
> sent as referrer information when making same-origin-referrer requests.
> Cross-origin-referrer requests will contain no referrer information.

## Decision

The application's one Referrer-Policy value is `strict-origin`. It is the
value of `Onetime::Middleware::Registry::REFERRER_POLICY`, and every emitter
reads that constant: Otto's `security_config.referrer_policy` for routed
responses, `Rack::Protection::ReferrerPolicy` for non-Otto responses, and the
`<meta name="referrer">` in the HTML head, which is what governs the
navigations the SPA starts.

Two constraints determine the value, and `strict-origin` is the only one that
meets both with the least disclosure:

1. **No path or query in any `Referer`, same-origin included** (audit M-3.2).
   This rules out the browser default and the OWASP Cheat Sheet
   recommendation, `strict-origin-when-cross-origin`, and it rules out
   `same-origin`: both send the full URL on same-origin requests, which
   would put secret paths into the application's own access logs and error
   reports. It also rules out `no-referrer-when-downgrade`,
   `origin-when-cross-origin`, and `unsafe-url`.
2. **A real `Origin` on the same-origin HTTPS form POST that starts SSO.**
   Per the Fetch algorithm above, this rules out `no-referrer`. Of the
   remaining values, `origin` and `strict-origin` both send origin only;
   `strict-origin` additionally sends nothing on an HTTPS to HTTP downgrade,
   so it is strictly tighter.

The alternative that keeps `no-referrer` is exempting `/auth/sso/*` from
`Rack::Protection::HttpOrigin`. That widens a CSRF gate on the authentication
surface to fix a header-policy problem, and it is rejected. `HttpOrigin`
refusing `Origin: null` is correct behavior and is retained.

Per ADR-048, the sources here do not determine the answer: the two OWASP
publications recommend different values and neither addresses the `Origin`
interaction. The choice of `strict-origin` is an OTS judgment derived from the
normative Fetch and Referrer Policy texts and the M-3.2 constraint.

## Trade-offs

- **We lose**: Referrer secrecy toward destinations. Under `no-referrer` a
  destination learned nothing about where the user came from. Under
  `strict-origin` every destination, same-origin or cross-origin, learns the
  scheme, host, and port of the referring page. For a custom domain the host
  is the tenant hostname, so an identity provider, a docs site, a billing
  provider, or any external link on an OTS page learns which tenant the user
  came from. This is origin-level disclosure, not a single bit.
- **We gain**: SSO sign-in works from every surface, on custom domains
  included, without weakening the Origin-based CSRF check. Secret paths and
  queries still never appear in a `Referer`, including in OTS's own logs.
- **Risk**: The policy is a single value for the whole application. A future
  page that must send no referrer at all cannot get it from this constant;
  it would need a per-element `referrerpolicy` attribute or a per-response
  override, and that override must not be applied to any page that starts a
  native form POST. Any change to the SSO initiation mechanism (for example,
  replacing the form POST with a fetch-then-navigate flow) removes constraint
  2 and reopens this decision.

## Related

- [ADR-048: Evidence Basis for Security Decisions](adr-048-evidence-basis-for-security-decisions.md)
- `lib/onetime/middleware/registry.rb` — `REFERRER_POLICY` and the
  `ReferrerPolicy` and `HttpOrigin` components
- `lib/onetime/application/base.rb` — `apply_referrer_policy`, the Otto
  emitter
- `apps/web/core/templates/partials/head-base.rue` — the document meta,
  pinned to the constant by `spec/integration/simple/rhales_migration_spec.rb`
- `src/shared/utils/sso.ts` — the native form POST that constraint 2 protects
- Issue #4542 — tenant SSO sign-in refused with `Origin: null`
