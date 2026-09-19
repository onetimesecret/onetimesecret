---
id: "016"
status: accepted
title: "ADR-016: Decouple Ownership Verification from Certificate/Serving Status"
---

## Status

Accepted

## Date

2026-06-30

## Context

`src/shared/composables/useDomainStatus.ts:41-47` derives every UI state
(`active`, `dns_incorrect`, `inactive`, `unverified`) from a single
Approximated `vhost.status` string plus a `vhost_fetch_failed_at` staleness
window. For `caddy_on_demand` and `passthrough` domains, `vhost` is never
populated, so the Domain Validation screen has no correct state to render —
this is the concrete cause of the reported "100% of domains show DNS
Incorrect" behavior under non-Approximated strategies.

On the backend, CNAME/A resolution is never independently checked by OTS
under any strategy. `CustomDomain#resolving` is purely a pass-through of
Approximated's `is_resolving` claim (`approximated_strategy.rb:164`) for
that one strategy, and is simply unset for the other two. TXT ownership
matching (`approximated_client.rb:64-70`) is likewise `approximated`-only.

Industry precedent, both confirmed 3-0 in research: Cloudflare for SaaS
models hostname-ownership validation and certificate validation as two
independent state machines that can be observably out of sync. Fly.io
requires proof via at least one of AAAA/CNAME *or* a dedicated TXT record,
treating "pointed at us" and "owned by this tenant" as separate,
independently-satisfiable signals. OTS's `verification_state` enum
(`custom_domain.rb:639-647`) is already structurally the ownership axis —
the gap is that (a) it's never populated independently of Approximated, and
(b) the frontend doesn't surface it as a distinct axis from cert/serving
status.

## Decision

**Two independent state axes, backend and frontend, for every strategy:**

1. **Ownership axis** (`verification_state`: unverified → pending →
   resolving → verified) — universal, computed the same way regardless of
   strategy. OTS performs its own TXT lookup (reusing the existing
   `txt_validation_host`/`txt_validation_value` fields, which already meet
   CA/Browser Forum's 112-bit entropy minimum via `SecureRandom.hex(16)`)
   instead of delegating that check exclusively to Approximated's API. This
   makes ownership proof available under `caddy_on_demand` and
   `passthrough`, where it doesn't exist today.
2. **Certificate/serving axis** — strategy-specific, never conflated with
   ownership. `approximated`: Approximated's `vhost.status` as today.
   `caddy_on_demand`: Caddy ACME issuance success/failure (which proves DNS
   resolution, not ownership — see below). `passthrough`: "managed
   externally," no axis to render.

CNAME/A resolution becomes an OTS-performed check (not a blind pass-through
of Approximated's `is_resolving`) for all strategies that need it, cross-checked
against Approximated's own claim where that strategy is in use rather than
trusted outright.

**Explicit non-conflation for `caddy_on_demand`**: a successful Caddy ACME
issuance proves the domain resolves to our infrastructure. It proves
**nothing** about account-level ownership. It must never be read as
equivalent to `verification_state == :verified`. This is the mechanism that
connects to the Issue 3 / ADR-017 takeover risk — `caddy_on_demand` getting
a cert auto-issued purely because DNS resolves, with no ownership check, is
the same exposure as `passthrough`'s lack of gating, just arrived at via the
certificate path instead of the link-creation path.

**Frontend**: `useDomainStatus.ts` is redesigned to key off
`validation_strategy` and render the two axes independently — an ownership
badge (always present, same semantics across strategies) and a
strategy-specific serving badge (Approximated detail view / Caddy
ready-or-not / "externally managed" note for passthrough). The DNS widget
continues to render only for `approximated` (existing behavior, README
table) since it's specific to that provider's onboarding flow.

## Trade-offs

- **We lose**: the simplicity of one status string covering both
  "is it theirs" and "is it serving." Two axes mean two things to test and
  two things to keep in sync in the UI.
- **We gain**: correct status display under all three strategies (fixes the
  reported "100% DNS Incorrect" bug), and an architectural seam that
  prevents a cert-issuance side effect from silently standing in for an
  ownership proof.
- **Risk**: building OTS's own TXT/CNAME lookup is new code surface (DNS
  resolution, timeouts, retry semantics) that didn't exist before for the
  non-Approximated strategies. Substantially mitigated: the sender-domain
  validation subsystem (`lib/onetime/domain_validation/sender_strategies/`,
  issue #2835) already implements parallel `Resolv::DNS` lookups with error
  isolation, retry with backoff, Redis-backed DNS rate limiting, and result
  caching — reuse that machinery rather than building a second DNS stack.
  Its test catalog (`docs/test-plans/dns-resilience-2835-qa-plan.md`) is the
  QA skeleton for this work.

## Implementation Notes

### Ownership axis implemented for `caddy_on_demand` (2026-09-18)

`CaddyOnDemandStrategy#validate_ownership` used to return `validated: true`
without checking anything, so any verify pass set `verified`. It now checks
the TXT challenge record through `DomainValidation::TxtVerifier`, with the
same "exactly one matching value" rule Approximated applies and the three
outcomes of `BaseStrategy#validate_ownership`:

- `true`: the record matches.
- `false`: the resolver stated the record is missing or different
  (NXDOMAIN, NOERROR without TXT data, other values). Demotes, unless a
  Colonel override holds the flag.
- `nil` / indeterminate: SERVFAIL, REFUSED, timeout, network error. Stored
  state is left alone.

The Trade-offs section suggests reusing the sender-domain DNS machinery.
That code uses `Resolv::DNS#getresources`, which returns `[]` for NXDOMAIN,
SERVFAIL and a timeout alike, so it cannot separate `false` from `nil`.
`DomainValidation::TxtResolver` sends the query itself and reads the
response code; it uses only the stdlib message codec.

`ApproximatedStrategy` uses the same verifier when Approximated's own lookup
fails (`actual_values: false`). A native negative fails a first-time check
closed, but does not revoke an existing verification without upstream
corroboration; a definitive negative from Approximated still demotes.

Order of work matters for the "ask gate is unsatisfiable" note below. The
OTS-side resolving check makes `ready?` reachable under `caddy_on_demand`;
the TXT check had to land first so that `verified` carries proof by the time
the gate can open. `passthrough` still performs no ownership check (ADR-017).

Operator impact: domains that were marked verified under `caddy_on_demand`
without a TXT record lose `verified` on the first check after upgrade,
unless the record exists or a Colonel override holds the flag. That includes
a first check that is indeterminate: the strategy returns `false` rather than
`nil` for a verified domain with no `verified_confirmed_at`, because such a
flag was never backed by a TXT check and the serving axis below would
otherwise make the domain `ready?`. Installs that do not run
`DomainRefreshJob` (the scheduler is off by default) need
`bin/ots domains verify --all` for any of this to reach existing domains.

`verified_confirmed_at` is written only for a pass from a strategy that
checks the record (`BaseStrategy#proves_ownership?`: `approximated` and
`caddy_on_demand`). A `passthrough` pass sets `verified` and records no
confirmation, so a domain verified under `passthrough` is treated as never
confirmed after a move to `caddy_on_demand`.

The never-confirmed rule also reaches an install that cuts over from
`approximated` to `caddy_on_demand` at or soon after this upgrade. The field
is new, so every domain starts without it, including those Approximated had
proven; and cutover is the first time the app needs its own working resolver
on every check. The operator sequence is: upgrade while still on
`approximated`; run a full `bin/ots domains verify --all` pass (or a complete
`DomainRefreshJob` walk) so the confirmation is recorded for every proven
domain; confirm the app host has a working resolver; then switch strategy.
Without that, a first lookup under `caddy_on_demand` that gets no answer
withdraws `verified` from a domain Approximated had proven, until the next
passing check or a Colonel override.

### Serving axis implemented for `caddy_on_demand` (2026-09-18)

`CaddyOnDemandStrategy#check_status` no longer returns `nil` for both fields.
It runs `DomainValidation::TlsProbe`:

- `is_resolving` comes from an OTS-performed A/AAAA lookup
  (`AddressResolver`, the same response-code-aware transport as
  `TxtResolver`): an address is `true`, NXDOMAIN or an empty NOERROR for both
  families is `false`, anything else is `nil` and leaves `resolving` alone.
- `has_ssl` comes from a TLS handshake to port 443 with SNI and full chain
  and hostname verification. No application data is sent.
- The hostname is customer-controlled, so the dial goes through
  `Onetime::Http::Guard`: one resolution, the whole address set rejected if
  any address is non-public, and the connection pinned to a vetted IP. A
  refused probe reports `is_resolving: true, has_ssl: nil`.

This makes the "ask gate is unsatisfiable" note below historical: `resolving`
is now written under `caddy_on_demand`, so `ready?` is reachable once the TXT
check has passed. `resolving` deliberately does not depend on the certificate
(Caddy cannot obtain one until the ask endpoint says yes), and it does not
compare the address with this deployment's. The Decision section's
"cross-checked" resolution target is still open for this strategy: there is
no configured expected address to compare against. Ownership rests on the TXT
check alone, as the non-conflation rule requires.

`has_ssl` is persisted inside the `vhost` blob. The strategy rewrites the
blob whenever `is_resolving` is known, so the blob's `status` and
`is_resolving` never disagree with the `resolving` field; when `has_ssl` is
unknown (port 443 unreachable, or the egress guard refused the address) the
stored `has_ssl` and certificate dates are carried into the new blob only
while the stored `ssl_active_until` is in the future. At or after expiry they
no longer establish an active certificate, so the blob omits the claim and
reports `PENDING_SSL` until a probe sees the current certificate. It returns
neither `:data` nor `:mode` when the probe learned nothing;
`VerifyDomain#persist_changes` then stores
nothing and sets `vhost_fetch_failed_at`. A `vhost` blob left by
`approximated` is not replaced (it is the orphaned-vhost chore's evidence).

The probe blob reuses Approximated's `status` values (`ACTIVE_SSL`,
`DNS_INCORRECT`) plus `PENDING_SSL`, so the single badge has correct data to
render wherever it is shown.

### Customer workspace under `caddy_on_demand` (2026-09-18)

Until this note the customer workspace hid the badge and the verification
screen on every non-`approximated` install: one flag,
`isApproximatedDomainValidation()`, gated `showVerificationStatus` in
`DomainHeader`, `DomainsTableDomainCell` and `DomainsTableActionsCell`, the
`DomainVerify` / `DomainDns` route guards and the post-add navigation. Under
`caddy_on_demand` a customer therefore could not see the TXT challenge, the
status, or a verify button, and no domain could become verified without the
operator relaying the record. The flag answered two unrelated questions, so
it is now two predicates in `src/utils/features.ts`, both read from one
capability table that is the only place the frontend interprets a strategy
name:

- `isDomainOwnershipChecked()` — the strategy requires the TXT record
  (`approximated`, `caddy_on_demand`; mirrors
  `BaseStrategy#proves_ownership?`). Gates the badge, the TXT record, the
  verify action, the route guards and `useDomainsManager.navigateAfterAdd`.
- `isApproximatedDomainValidation()` — the domain points at the Approximated
  proxy. Gates only the proxy targets (`cluster.proxy_ip` / `proxy_host`)
  and the Approximated DNS widget.

Where the address record points is `useDomainDnsRecord`, shared by
`VerifyDomainDetails`, `DomainVerify` and `DomainDns`. Without the
Approximated proxy it is this install by name: CNAME, or ALIAS/ANAME for an
apex, to `canonical_domain`, falling back to `site_host` (both already in the
bootstrap payload, and what `DomainDns` showed for `passthrough`). No backend
addition was needed. The backend has no configured address for this strategy
(the Decision's "cross-checked" resolution target is still open, see above),
so an A record to an IP is not offered; the apex notice says an A record to
the server's IP is the alternative. The proxy fields are not read at all
under `caddy_on_demand`: an install keeps them configured after a cutover for
the orphaned-vhost chore, and showing them would send new domains to
Approximated.

`useDomainStatus.ts` is still keyed on the blob's `status`, not on
`validation_strategy`; the Decision's per-strategy keying turned out not to
be needed because the probe writes the shared values. `PENDING_SSL` is the
one addition, and it is read together with `verified`, because under this
strategy Caddy may only obtain a certificate once the ACME endpoint sees a
verified domain:

- verified: "Certificate pending". Not an error and not a warning; nothing
  for the customer to do.
- not verified: "Pending Verification", in the warning style, linking to the
  verification page. Without this the badge would promise a certificate that
  cannot be issued.

The same rule applies to the active statuses (`ACTIVE`, `ACTIVE_SSL`,
`ACTIVE_SSL_PROXIED`): they read "Active" only for a verified domain. After a
demotion (the TXT record is removed and a check gets a definitive negative)
the certificate Caddy issued earlier keeps serving until it expires, so the
probe keeps writing `ACTIVE_SSL` while `verified` is false and `ready?` is
false. Such a domain reads "Pending Verification", links to the verification
page and loses the Manage quick action, the same as a resolving domain that
never passed. A verified domain, including one verified by override, is
unaffected under either strategy.

"Unverified" is kept for the stale case only (the last status fetch failed
within the freshness window), so "could not tell" and "not verified" are
different text, not just different icons. The icons are decorative, and the
status link in the domain list puts the status text in its accessible name.

`PENDING_SSL` is also what the blob says when `has_ssl` is unknown and the
stored certificate dates have lapsed. The badge cannot tell that apart from a
first certificate; the status table can, and its SSL row reads "Unknown"
rather than "Inactive" when `has_ssl` is absent.

### Caddy `ask` deprecation — confirmed in the app itself, not just the example file (2026-06-30)

Caddy's live config-docs API (`GET https://caddyserver.com/api/docs/config/apps/tls/automation/on_demand/`,
backing the human page at
[`/docs/json/apps/tls/automation/on_demand/`](https://caddyserver.com/docs/json/apps/tls/automation/on_demand/))
returns the `OnDemandConfig` struct verbatim:

- `ask` (string): *"Deprecated. WILL BE REMOVED SOON. Use 'permission'
  instead with the `http` module."*
- `permission` (module, **REQUIRED**): *"A module that will determine
  whether a certificate is allowed to be loaded from storage or obtained
  from an issuer on demand."*

The Caddyfile adapter still accepts `ask <endpoint>` today alongside
`permission <module>` (confirmed via
[`/docs/caddyfile/options`](https://caddyserver.com/docs/caddyfile/options)
— both directives are listed as valid inside `on_demand_tls { }`), so this
is not yet a hard error. But the JSON-level field is marked for removal,
and Caddy already refuses to boot on-demand TLS with **no** permission
mechanism configured at all.

This is not a stale-example-file issue — it's load-bearing in
`apps/internal/acme/`. The deprecated `ask` directive is the app's
organizing concept, not a comment:

- `routes.txt:6` — the literal route is `GET /ask`
- `application.rb:34` — the handler class is named `AskHandler`
- `application.rb:14-17` — the header comment documents the Caddy
  `on_demand_tls { ask ... }` config form
- `README.md:73-89` ("Caddy Integration") documents `ask` as *the*
  integration method, with a full worked Caddyfile example
- Zero references to `permission` anywhere in `apps/internal/acme/`
  (confirmed via repo-wide grep) — no migration started

Migration is mechanical, not a redesign: Caddy's `http` permission module
(`PermissionByHTTP`, confirmed via
`GET /api/docs/config/apps/tls/automation/on_demand/permission/http/`) has
the **identical contract** the app already implements — a single
`endpoint` URL, `?domain=` query param appended, 200 OK = allowed,
anything else = denied, redirects not followed. The existing
`/api/internal/acme/ask` route, `AskHandler`, and `domain_allowed?` logic
need no behavior change — only the Caddy-side config moves from:

```caddyfile
on_demand_tls {
  ask http://127.0.0.1:12020/api/internal/acme/ask
}
```

to:

```caddyfile
on_demand_tls {
  permission http {
    endpoint http://127.0.0.1:12020/api/internal/acme/ask
  }
}
```

Do this migration (config + README + `etc/examples/Caddyfile-example:67-69`,
which also still shows the deprecated form, currently commented out) as
part of this ADR's work, before a future Caddy release turns `ask` into a
hard error.

### Separate, smaller doc-drift item: `check_verification` (2026-06-30)

`README.md:24,30,81-89` documents `check_verification=false` as a
supported query parameter to skip DNS ownership proof during initial
setup. `application.rb:46-49`'s own code comment says this parameter "was
removed from the HTTP interface to prevent any local process from
bypassing DNS verification via query string" — `AskHandler.call` always
calls `domain_allowed?(domain)` with no `check_verification` argument. The
README is stale on this specific point; not part of this ADR's scope, but
should be corrected (or the parameter reinstated, if the setup-flow need it
documented is real) independent of the `ask`→`permission` migration.

### Ask endpoint performance — verified compliant, no change needed (2026-06-30)

Caddy requires the ask/permission callback to respond in a few milliseconds
via constant-time indexed lookup, with no DNS queries or network requests.
Code-checked: `Application.domain_allowed?`
(`apps/internal/acme/application.rb:140-156`) does an indexed Redis lookup
(`CustomDomain.load_by_display_domain`) then `ready?`, which is a pure
in-memory boolean check with no I/O. This already meets the guidance — no
remediation needed here, only confirmed and documented.

### ACME `ask` gate is unsatisfiable under `caddy_on_demand` today — makes this ADR a functional prerequisite, not just UI/ownership polish (2026-07-03, re-verified against current source 2026-07-05)

> Resolved 2026-09-18: see "Serving axis implemented for `caddy_on_demand`"
> above. The analysis is kept as written.

The `ask` endpoint gates cert issuance on `ready?` ⇔
`verification_state == :verified` (`custom_domain.rb:656`, `639-647`), which
requires `resolving.to_s == 'true'`. The `domain.resolving` field is written
in exactly one place — `VerifyDomain#persist_changes`
(`lib/onetime/operations/verify_domain.rb:307-331`) — and that write is
gated on the strategy's `check_status` returning a **non-nil** `is_resolving`:

```ruby
# verify_domain.rb:314-315
unless status_result[:is_resolving].nil?
  domain.resolving = status_result[:is_resolving].to_s
end
```

`caddy_on_demand`'s `check_status` returns `is_resolving: nil`
(`caddy_on_demand_strategy.rb:61`), and `field :resolving`
(`custom_domain.rb:93`) has no default. So under `caddy_on_demand`:
`resolving` is never written → stays nil → `nil.to_s == 'true'` is false →
`verification_state` caps at `:pending` → `ready?` is never true →
`domain_allowed?` returns false → **the `ask` endpoint returns 403 for every
domain, and Caddy can never obtain a certificate.** The strategy whose entire
purpose is Caddy on-demand TLS calling this endpoint cannot serve a single
domain until this ADR's OTS-side resolving check ships.

(Note: the `is_resolving: status_result[:is_resolving] || false` on
`verify_domain.rb:162` coerces nil→false only in the returned `Result`
struct — it does **not** write the persisted `resolving` field, which remains
governed by the nil-guard above.)

This reclassifies ADR-016 from a UI-correctness / ownership-axis improvement
to a **functional prerequisite** for `caddy_on_demand` end-to-end usability.

Two facts that bound the claim, both code-checked:

- **`passthrough` is unaffected** — its `check_status` hardcodes
  `is_resolving: true` (`passthrough_strategy.rb:54`), so its resolving axis
  can be set. Do not lump `passthrough` in with `caddy_on_demand` here; this
  consequence is caddy-specific. `approximated` is likewise unaffected (it
  returns a real `is_resolving`).
- **The 403-under-caddy behavior is untested.**
  `apps/internal/acme/spec/application_spec.rb:31-39` stubs
  `CustomDomain.load_by_display_domain` to return doubles with hardcoded
  `ready?: true/false`; it never exercises the real strategy → `check_status`
  → `persist_changes` → `resolving` path, which is why CI is green on a
  strategy that returns 403 for everything.

### Localhost-only gate trusts `REMOTE_ADDR` — unconfirmed enumeration lead, not an asserted vector (2026-07-03)

The `ask` endpoint is fronted by a `LocalhostOnly` middleware that reads
`env['REMOTE_ADDR']` (`apps/internal/acme/application.rb:69-77`). The app's
own comment (`application.rb:65-66`, `116-119`) states it relies on
`IPPrivacyMiddleware` (from the universal MiddlewareStack) having already
rewritten `REMOTE_ADDR` from forwarded headers. **If** that upstream rewrite
trusts `X-Forwarded-For`/`Forwarded` from untrusted peers, a spoofed
`X-Forwarded-For: 127.0.0.1` could pass the localhost gate and let an
external caller enumerate which domains are registered/verified (200 vs 403).

This is recorded as a lead, **not** an asserted vulnerability: the exact
trust boundary of `IPPrivacyMiddleware` was not traced end-to-end, and the
#3436 trusted-proxy harmonization (otto 2.3.1, RFC 7239 depth) governs how
forwarded headers are trusted. Before treating this as real, confirm
`IPPrivacyMiddleware`'s peer-trust configuration against the #3436 model. The
endpoint response body is a bare `OK`/`Forbidden`, so any enumeration is
boolean-only — no domain listing is leaked directly.

### TXT challenge has no expiry (2026-06-30)

`generate_txt_validation_record` (`custom_domain.rb:589-617`) generates
`txt_validation_value` once; no code path expires or rotates it. CA/Browser
Forum BR allows reuse up to 30 days; OTS currently has no upper bound at
all. Candidate to fold into ADR-018's bounded-lifecycle work rather than a
fifth ADR — flagged here, decided there.
