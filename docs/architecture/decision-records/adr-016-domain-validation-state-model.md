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
