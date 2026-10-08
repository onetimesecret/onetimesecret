# Public-host review follow-up validation

Assessment date: 2026-10-03. Baseline: `4653aa03eb2d48f68f1bb57f03cf8c311a4f5cb4`,
plus the uncommitted test changes listed below. No production policy was changed,
and no commit was created. This is an execution record and finding ledger, not
an accepted security policy or a claim that the remaining behavior is safe.

## Status as of 2026-10-07

Added after v0.26.15 (#4682). The execution record below is the 2026-10-03
run at its baseline and is left as written. This table says what has closed
each finding since and where main pins it. Paths are relative to the
repository root.

| Finding | Status on main | Closed by | Pinned in |
| --- | --- | --- | --- |
| H-02 cached selection skips scope | Closed for the cache and the selection paths. Open: the two-custom-domain scope decision (#4697, ADR-050) and the listing risk `RISK-2026-08-14-M06`. | b63aec32c in #4661: the loader keeps no session cache and resolves membership, archived state and scope on every call; the header and session-selection paths share one check. #4672: an unregistered display host withholds every organization. | `spec/unit/organization_loader_cache_scope_spec.rb` (header: the scope is applied to the fallback steps, the `O-Organization-ID` header and the explicit session selection) |
| H-03 origin admission on an `:invalid` host | Closed | #4673 (f99666234): `HttpOriginOptions` admits `https://{display domain}` only for a host classified `:canonical`, `:subdomain` or `:custom`. An `:invalid` host with an absent lookup is refused; one whose read failed is still admitted so the application's own refusal answers. | `spec/unit/onetime/middleware/http_origin_options_spec.rb`; `apps/web/auth/spec/integration/full/host_proxy_stateful_boundaries_spec.rb`, "H-03: unregistered display host on the auth mount" |
| H-04 lookup-failure responses | Closed as a response contract. A failed read still refuses the request; that is the fail-closed answer, not an open finding. | #4675 (46766ff30): one answer whatever the read raised, 503 `Onetime::DomainUnavailable` on the Rodauth routes and `/signin?auth_error=domain_unavailable` on SSO initiation; no email, no IdP URL, reset keys untouched. The 500 and the `sso_failed` redirect in the table below are gone. | `apps/web/auth/spec/integration/full/host_proxy_failure_responses_spec.rb` |
| H-05 request-derived reset destination with `site.host` unset | Closed | ff8b11509 (within #4623): `required_base_url!` and `required_credential_base_url!` in `apps/web/auth/lib/public_host.rb` raise `Auth::PublicHost::MissingAllowlistedOrigin` instead of falling back to Rack's authority. | `apps/web/auth/spec/integration/full/host_proxy_matrix_spec.rb`, rows H05-E01 to H05-E07; `apps/web/auth/spec/integration/full/public_host_fallback_spec.rb`, "refuses without an account SELECT, INSERT, email, or persisted reset key", "also refuses direct reset-key creation before the database write", "gives the same refusal for existing and missing accounts" |

Items 1 (deployment coverage) and 5 (validation disclosure) and the
trust-boundary table are unchanged by this. The deployed provider, edge and
server path remains uninventoried.

## Disposition of the five review items

| Review item                              | Disposition                                                   | Evidence and remaining work                                                                                                                                                                                                                                                           |
| ---------------------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. Coverage gaps                         | Application coverage executed; deployment coverage incomplete | Scheme conflicts, unknown-host emitters, session replay, cookies, CSRF/origin, and admin gates ran. The real Caddy fixture passed, but ends at a Python capture server. Deployed ingress and application-server parsing remain unverified.                                            |
| 2. H-02 authorization                    | Reproduced selection inconsistency; unresolved                | Ordinary and matching-header cache hits skip domain scope. Changing host selection or adding host-only cache keys is insufficient. Downstream audit-list authority has a separate existing scope risk; this reproduction does not establish a cache-caused privilege escalation.      |
| 3. H-03 origin / H-05 sensitive fallback | Assessed independently of proxy equivalence; H-05 unresolved  | Matching invalid display-domain origins are admitted, while tested recovery, SSO, and session mutation gates refuse access. Missing `site.host` can produce request-derived credential-bearing reset emails on reachable sign-in surfaces. No token collection/redemption was tested. |
| 4. H-04 availability                     | Response behavior reproduced; availability concern retained   | Redis lookup errors produce reset HTTP 503; unexpected runtime errors produce reset HTTP 500. SSO converts both into its failure redirect. Legitimate registered tenants can encounter lookup failures. Natural runtime-error causes and frequency were not established.              |
| 5. Validation disclosure                 | Addressed for this execution record                           | Final runs report failures and pending counts. All selected integration examples ran, including email/SSO assertions. This does not retroactively validate the earlier 208-example report or other SSO specs that retain skip guards.                                                 |

## Findings and concrete reproductions

### H-02: cached organization selection skips scope validation

*2026-10-07: closed for the cache and the selection paths; see [Status as of 2026-10-07](#status-as-of-2026-10-07).*

[Organization loader reproduction](../../spec/unit/organization_loader_cache_scope_spec.rb)
covers rewrite off/on, ordinary and matching-header caches, expiry, explicit
session selection, and a membership-scope change without changing hosts.

With rewrite on, cold/expired selection rejects an organization on a denied
sibling-domain request. A warm cache returns it without calling
`can_access_domain?`. With rewrite off, selection can instead fall through using
the backend Host. Explicit session selection also returns the organization.
These are distinct paths; changing only the host source does not fix all of them.

The test passes loader context into real `ListReceipts` authorization. With
active membership and explicit `api_access`/`audit_logs` grants, the organization
receipt index is read; without `audit_logs`, it is not. Non-owner bearer fields
remain redacted. Storage, receipt association, and entitlement grants are doubles:
the test does not establish a real sibling-domain receipt or browser-session
exploit. Organization-wide audit listing is already reachable from an allowed
surface, so this is not proof that the cache grants new audit authority.

The [active security risk register](../../docs/security/active-risk-register.md)
retains `RISK-2026-08-14-M06` as Open: “A domain-scoped member with `audit_logs`
can read sibling-domain receipt metadata.” That is the existing listing risk,
not an acceptance of the cache behavior. Next: define selection/cache/session
scope policy and reproduce the chosen protected operation with real membership,
receipt-domain association, and a session that legitimately reaches the request.
H-02 remains unresolved; no severity is inferred from provenance.

### H-03: origin acceptance is broader than protected-route admission

*2026-10-07: closed by #4673; see [Status as of 2026-10-07](#status-as-of-2026-10-07).*

[Stateful boundary tests](../../apps/web/auth/spec/integration/full/host_proxy_stateful_boundaries_spec.rb)
exercise unregistered preserved and forwarded hosts with rewrite off/on.
A foreign Origin is refused; an HTTPS Origin matching the invalid display domain
is admitted. Recovery then returns 404 without a reset key/email; SSO refuses
without an IdP redirect. A replayed canonical session with a valid CSRF token
cannot change the password: it receives `surface_mismatch`, and the session ends.
The anonymous secret-status route, with its origin middleware enabled, accepts
the matching origin and returns an empty result.

The existing canonical-backend-Origin logout comparison also runs: acceptance
with rewrite off becomes 403 with rewrite on. These observations establish
origin admission and specific downstream controls, not a general CSRF exploit
or universal unknown-host rejection. Next: assess other origin-protected routes
with concrete credentials/data and actual browser cookie delivery. Broader origin
policy remains unresolved rather than accepted through proxy equivalence.

### H-05: missing `site.host` can emit a request-derived reset destination

*2026-10-07: closed by ff8b11509; see [Status as of 2026-10-07](#status-as-of-2026-10-07).*

[Emitter matrix](../../apps/web/auth/spec/integration/full/host_proxy_matrix_spec.rb)
now distinguishes unchanged configuration from actual `site.host: nil`, verifies
the nil value, and restores configuration/classifier state afterward.
Fourteen examples run real mounted SSO and recovery requests with missing host
configuration, including positive controls and refusals.

- Configured canonical and verified-tenant tiers retain their selected origins.
- An unverified tenant with password sign-in enabled receives a reset link based
  on Rack authority. Behind the rewriting proxy, this is the backend authority
  with rewrite off and the unverified tenant authority with rewrite on.
- With domains disabled and global sign-in enabled, an unregistered request Host
  becomes the reset-link destination when `site.host` is absent.
- With domains enabled, tested unregistered hosts remain recovery-gated; a failed
  tenant lookup emits no credential. Unverified/unregistered SSO remains refused.

These examples construct credential-bearing email at the captured queue boundary
and verify persisted reset keys. They do not send external mail or redeem tokens.
Risk requires the missing-host configuration, a reachable recovery route, and
control of the resulting destination. H-05 remains unresolved. Next: choose and
enforce a missing-canonical-host policy, then retest these emitter paths; proxy
compatibility alone is not a security disposition.

### H-04: failed tenant lookup has a visible availability consequence

*2026-10-07: closed by #4675, which replaced the responses in the table below with one domain-unavailable answer; see [Status as of 2026-10-07](#status-as-of-2026-10-07).*

[Failure-response tests](../../apps/web/auth/spec/integration/full/host_proxy_failure_responses_spec.rb)
first establish healthy verified-tenant SSO/email behavior, then inject lookup
errors with rewrite off/on.

| Lookup error       | SSO initiation                         | Password-reset request                           |
| ------------------ | -------------------------------------- | ------------------------------------------------ |
| `Redis::BaseError` | 302 to `/signin?auth_error=sso_failed` | 503, `SigninPolicyUnavailable`, `Retry-After: 5` |
| `RuntimeError`     | 302 to `/signin?auth_error=sso_failed` | 500, generic `ServerError`                       |

Classification becomes invalid; rewrite does not occur. No failed request emits
an email or IdP authorization URL, and failed reset requests preserve existing
reset keys. Private exception details and fixture secrets are absent from the
response body. Logs were not audited for scrubbing. The exception is injected
at `CustomDomain.from_display_domain`; the stack and stores are real. Controlled
Redis rejection does not eliminate outage impact; unexpected-error 500 remains
part of the baseline. Next: identify natural unexpected-error triggers and
establish whether the response contract should normalize those failures.

## Execution evidence

All Ruby execution used the lane runner in a checkout with `.test-mode` present.
Final commands were run after the test edits, against the combined working tree.
`git --no-pager rev-parse HEAD` recorded the baseline SHA immediately before and
after the final sequential integration/unit rerun. The changed Ruby files were
not edited between those runs and this report:

```sh
tests/lanes/run full-sqlite --only apps/web/auth/spec/integration/full/host_proxy_matrix_spec.rb --only apps/web/auth/spec/integration/full/host_proxy_stateful_boundaries_spec.rb --only apps/web/auth/spec/integration/full/host_proxy_failure_responses_spec.rb -- --format progress --format json --out tmp/host-proxy-followup-full.json

tests/lanes/run unit --only spec/unit/organization_loader_cache_scope_spec.rb --only spec/unit/onetime/middleware/public_host_rewrite_spec.rb --only spec/unit/onetime/middleware/public_host_rewrite_adversarial_spec.rb --only spec/unit/onetime/middleware/strip_forwarded_host_spec.rb -- --format progress --format json --out tmp/host-proxy-followup-unit.json

python3 tools/host-seam/proxy-wire.py fixture --caddy /Users/d/go/bin/caddy > tmp/host-proxy-followup-wire.jsonl
```

The Caddy path is the local installed binary used for this run, not a portable
installation instruction. Its reported version was `v2.11.4`.

| Final execution                     | Examples/cases | Failures | Pending/skipped | Exit |
| ----------------------------------- | -------------: | -------: | --------------: | ---: |
| Full SQLite integration, seed 34689 |            368 |        0 |               0 |    0 |
| Unit, seed 10185                    |            352 |        0 |               0 |    0 |
| Caddy HTTP/1.1 wire fixture         |             20 |        0 |               0 |    0 |

RSpec JSON records all 720 selected examples as passed, with zero outside-example
errors. Missing-host rows executed: 10 captured reset emails, four IdP redirects,
and ten SSO refusals. The emitters require org SSO at boot through a failing
precondition, not a skip. Existing loader Tryouts also ran separately: 29 passed,
zero failed; that runner did not report a separate skip count.

Earlier development runs were not all green: the new failure-response spec
initially had eight matcher errors (8 examples); matrix/stateful additions
initially had eight expectation errors (360 examples). Those assertions were
corrected before the final combined runs. H-02 development also encountered
datastore-lock refusals, a corrected require-path load error, and a runner refusal
to mix Tryouts/RSpec files in one command. Those were not passing coverage.

Local JSON/log artifacts are under `tmp/`; they are not committed CI evidence.
Neither full lane was run in its entirety. PostgreSQL, billing overlays, CI,
external email delivery, and IdP authentication/callback completion were not run.

## Trust-boundary coverage limits

| Boundary                            | Executed evidence                                                            | Not established                                                                           |
| ----------------------------------- | ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Proxy trust and host classification | Trust-state/host adversarial matrix; mounted host matrix                     | Production trust configuration, direct-origin exclusion, universal correct classification |
| Scheme and port handling            | Conflicting/hostile schemes and port/base-URL agreement                      | TLS termination or HTTP/2–3 translation on deployed ingress                               |
| Header overwrite and duplicates     | Caddy 2.11.4 raw HTTP/1.1 capture; duplicate Host returns 400 in both orders | Provider/edge chain, actual app-server parsing, HTTP/2–3 duplicates                       |
| Sensitive URLs                      | Mounted recovery/SSO emission, real missing-host configuration               | Token collection/redemption, external mail, IdP completion                                |
| Tenant authorization                | Loader characterization and real downstream gates with doubles               | Browser exploit, real sibling receipt association, approved cache/session scope policy    |
| Sessions and cookies                | Real login/store/replay across surfaces; host-only attributes                | Browser cookie delivery; production Secure attribute (lane uses `secure:false`)           |
| CSRF/origin                         | Missing/invalid tokens, matching/foreign origins, protected mutation refusal | Every route, browser CSRF exploit, accepted invalid-host origin policy                    |
| Admin isolation                     | Canonical role control; tenant host rejection with real colonel session      | Every deployment listener or proxy bypass                                                 |
| SAML callbacks                      | None in these selected runs                                                  | SAML initiation, ACS validation, and callback binding                                     |

## Conclusion

The five concerns now have explicit evidence and dispositions. Added coverage
and passing fixtures do not close H-02, broader origin policy, or H-05, nor do
they remove H-04's availability consequence. Security resolution remains
incomplete. The deployed provider/edge/server path and origin boundary still
require inventory, authorized staging, origin-side observations, and appropriate
operator policy decisions before a deployment-level acceptance claim.

What has closed since this record was written is in
[Status as of 2026-10-07](#status-as-of-2026-10-07).
