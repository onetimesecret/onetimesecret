---
id: "016"
status: proposed
title: "ADR-016: Decouple Ownership Verification from Certificate/Serving Status"
---

## Status

Proposed

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
(`custom_domain.rb:608-616`) is already structurally the ownership axis —
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
  non-Approximated strategies.

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

### TXT challenge has no expiry (2026-06-30)

`generate_txt_validation_record` (`custom_domain.rb:558-586`) generates
`txt_validation_value` once; no code path expires or rotates it. CA/Browser
Forum BR allows reuse up to 30 days; OTS currently has no upper bound at
all. Candidate to fold into ADR-018's bounded-lifecycle work rather than a
fifth ADR — flagged here, decided there.
