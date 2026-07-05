# docs/specs/domain-validation/domain-validation-policy.md
---
# Custom Domain Validation Policy

Itemizes known gaps in the multi-strategy domain validation system
(`lib/onetime/domain_validation/`) and the research that grounds the four
decisions recorded as ADR-015 through ADR-018. This is the substrate
document — read it for "why"; read the ADRs for "what was decided."

Research method: 6 web-search angles, 23 sources fetched, 94 claims
extracted, 25 adversarially voted (3-vote refute panel), 20 confirmed / 5
refuted. Full source list and per-claim vote record kept in the research
transcript (workflow run `wf_ff00e328-fc9`, 2026-06-30); this doc carries
forward only the claims that survived verification.

## Current Architecture (ground truth)

Three strategies behind a factory (`lib/onetime/domain_validation/strategy.rb`),
selected by a single **install-level** config key
`features.domains.validation_strategy` (default: `passthrough`,
`etc/defaults/config.defaults.yaml:504-509`). No per-domain or per-region
override exists anywhere, not even as a TODO.

| Strategy | Ownership proof | Cert/serving | DNS check | File |
|---|---|---|---|---|
| `approximated` | TXT, exact-match via Approximated API | Approximated-managed | TXT only; CNAME/A trusted from provider's `is_resolving` | `approximated_strategy.rb:33-255` |
| `caddy_on_demand` | None (Caddy ACME challenge ≠ ownership proof) | Caddy on-demand TLS | None performed by OTS | `caddy_on_demand_strategy.rb:17-99` |
| `passthrough` | None — always returns true | External/operator-managed | None | `passthrough_strategy.rb:16-92` |

`CustomDomain` (`lib/onetime/models/custom_domain.rb`) verification state
machine (`verification_state`, lines 639-647):

```
:unverified → :pending → :resolving → :verified
```

`:unverified` = no `txt_validation_value`. `:pending` = challenge set,
`resolving` field false. `:resolving` = `resolving` true, `verified` false.
`:verified` = both true. `ready?` (lines 656-658) ⇔ `:verified`. This method
does a pure in-memory boolean check on already-loaded fields — no DNS or
network I/O — **confirmed compliant** with Caddy's documented "ask/permission
endpoint must be a fast, constant-time, network-free lookup" guidance (see
Issue 4 / Additional Gap 3 below).

The TXT challenge (`generate_txt_validation_record`, lines 589-617) uses
`SecureRandom.hex(16)` (line 605) — 128 bits, CSPRNG-sourced — **confirmed
compliant** with the CA/Browser Forum Baseline Requirements 112-bit minimum
entropy for domain-control Random Values. **Gap confirmed by code read:**
the value is generated once and never expires or rotates — no code path
regenerates it on a timer or on repeated validation failure.

## Known Issues

### 1. UI is 100% Approximated-shaped — confidence: high

`src/shared/composables/useDomainStatus.ts:41-47` derives all four UI states
(`active`, `dns_incorrect`, `inactive`, `unverified`) from Approximated's
single `vhost.status` string plus a `vhost_fetch_failed_at` staleness window.
For `caddy_on_demand`/`passthrough`, `vhost` is never populated, so the
component has no correct state to render.

Industry pattern (Cloudflare for SaaS, 3-0 verified): hostname-ownership
validation and certificate validation are modeled as **two independent state
machines** with separate fields — they can be observably out of sync
(`status: active` while `ssl.status` is not). OTS already has the backend
analog of the ownership axis (`verification_state`) but collapses it with
the cert/serving axis into one Approximated-shaped string on the frontend.
→ ADR-016.

### 2. No per-domain validation strategy — confidence: low (no external precedent)

Config is install-level only. The verified evidence pool contains **no**
comparable-platform precedent for per-tenant-domain strategy selection —
Cloudflare, Fly.io, and CA/Browser Forum sources all describe single-backend
systems from the customer's perspective. This is an internal
cost/migration-economics decision (incremental regional cutover off
Approximated), not an externally-validated best practice. Recorded honestly
as such in ADR-015 — no industry citation is asserted for the "why," only
for the "how" (the strategy interface itself doesn't need to change shape).

### 3. Passthrough gating gap — confidence: high, reframed by research

Under `passthrough`, `validate_ownership()` always returns `true` and
`check_status()` always reports `ready: true`. Combined with
`features.domains.require_verified` defaulting to `false`
(`apps/api/v1/logic/secrets/base_secret_action.rb:456-461`), **any domain
string can be attached to an account and used to create links with zero
ownership proof.**

The team's original framing was UX ("a domain can get stuck in DNS
Incomplete forever, so we can't safely gate"). Research reframes this as a
**security** issue, not primarily a UX one: OWASP's subdomain/domain-takeover
pattern (3-0 verified) is "a DNS record points at a resource with no
ownership tie." Under `passthrough` this happens in the *other* direction —
the customer doesn't need a real DNS record at all; they need only type a
domain string into OTS to start serving branded secret links under it. If
that string belongs to someone else (typo, expired/dangling domain, a domain
the customer doesn't control), OTS becomes the vector.

The "stuck forever" blocker is also addressed by the research, separately:
Cloudflare's and ACME's (RFC 8555) validation lifecycles are **bounded** —
finite exponential backoff terminating in an automatic state transition, not
indefinite pending. A one-time ownership check at attach-time does not
depend on a mature always-on re-check pipeline to be safe to enable. →
ADR-017.

### 4. CNAME/TXT checking inconsistent — confidence: high

TXT matching is real but `approximated`-only, and delegated entirely to
Approximated's API (`approximated_client.rb:64-70`,
`check_records_match_exactly`). CNAME/A resolution (`resolving` field) is
**never independently checked by OTS code under any strategy** — it is
purely a pass-through of Approximated's `is_resolving` claim
(`approximated_strategy.rb:164`) for that one strategy, and entirely absent
for the other two.

Fly.io's model (3-0 verified) treats "pointed at us" (AAAA/CNAME) and "owned
by this tenant" (TXT) as two **separate, independently-satisfiable** proofs.
OTS's `caddy_on_demand` strategy risks conflating these: a successful Caddy
ACME issuance proves DNS points here, but proves nothing about
account-level ownership — if that's ever read as equivalent to "verified,"
it inherits the Issue 3 risk. → ADR-016.

### 5. No periodic re-validation with configurable sampling — confidence: high, requirement contradicted by evidence

The only existing job (`lib/onetime/jobs/scheduled/domain_refresh_job.rb`)
is disabled by default (`jobs.domain_refresh.enabled`, line 42), and when
enabled does a **full sweep** of all domains in batches of 200 every 30
minutes (lines 46, 71-75) — not a percentage sample.

The team's stated requirement ("random sampling with a configurable
percentage") does **not** match what the verified evidence shows comparable
systems doing. Cloudflare and RFC 8555 both use **per-domain** exponential
backoff with bounded retry counts and automatic terminal-state expiry — every
domain gets checked, but on a schedule that lengthens for stable domains and
gives up (to an explicit, recoverable failure state) for chronically-broken
ones. This is flagged as a direct contradiction of the stated requirement,
not smoothed over — see ADR-018 for the reversal and rationale, presented
for explicit sign-off. → ADR-018.

## Additional Gaps Surfaced by Research (not on the original list)

**1. Domain-takeover exposure is highest under `passthrough`/`caddy_on_demand` — confidence: high.**
Same root cause as Issue 3, elevated to its own item because it's a
distinct risk class (OWASP Subdomain Takeover Prevention Cheat Sheet,
3-0): OTS's shared infrastructure becomes the dangling target if a
domain is pointed here, gets a cert auto-issued by `caddy_on_demand`
purely because DNS resolves, without ever proving account ownership.
Strongest, best-evidenced new finding — folded into ADR-017.

**2. Caddy's `ask` config key is deprecated — confidence: high, confirmed live in this repo's actual ACME app, not just an example file.**
Caddy's live config-docs API (`GET /api/docs/config/apps/tls/automation/on_demand/`)
marks `ask` *"Deprecated. WILL BE REMOVED SOON. Use 'permission' instead
with the `http` module"* and `permission` as **REQUIRED**. The Caddyfile
adapter still accepts `ask` today (not yet a hard error, confirmed via
`/docs/caddyfile/options`), but it's on a removal path. This isn't a
stale-example-file issue — `apps/internal/acme/`'s entire identity is
built around `ask`: the route is literally `GET /ask`
(`routes.txt:6`), the handler class is `AskHandler`
(`application.rb:34`), and `README.md:73-89`'s full integration guide
documents the `ask` form. Zero references to `permission` exist anywhere
in `apps/internal/acme/`. Migration is mechanical — Caddy's `http`
permission module has an identical endpoint/response contract to what the
app already implements — but it hasn't been started. See ADR-016 for the
full citation and migration snippet.

**3. Ask-endpoint performance — confidence: medium, but verified compliant in OTS's case.**
Caddy's docs require the ask/permission callback to respond in a few
milliseconds via constant-time indexed lookup, with no DNS queries or
network requests, because a slow response stalls the TLS handshake.
Code-checked directly: `Application.domain_allowed?`
(`apps/internal/acme/application.rb:140-156`) calls
`CustomDomain.load_by_display_domain` (indexed Redis lookup) then
`ready?` (pure in-memory boolean check, no I/O) — **this is compliant**,
not a violation. Recorded here so the spec doesn't leave it as an open
question.

## Policy Decisions

| Issue | Decision | ADR |
|---|---|---|
| 1, 4 (partial) | Split ownership-verification and certificate/serving into two independent state axes, backend and frontend; OTS performs its own CNAME/A + TXT checks instead of trusting only Approximated's claims | ADR-016 |
| 2 | Add per-domain `validation_strategy` override field, install-level value as default/fallback | ADR-015 |
| 3, Additional Gap 1 | Gate domain-dependent functionality (link creation) on ownership-verification state, independent of the global `require_verified` flag, for strategies with no native ownership proof | ADR-017 |
| 5 | Replace the full-sweep/percentage-sample framing with per-domain exponential backoff and a bounded, terminal failure state | ADR-018 |

## Open Questions (not resolved by this research pass)

- Should `txt_validation_value` gain an explicit expiry/rotation policy
  (e.g., regenerate after N days unverified)? Confirmed gap, no decision
  recorded yet — candidate for ADR-018's bounded-lifecycle work to absorb
  rather than a fifth ADR.
- Per-domain strategy override (Issue 2) has no external benchmark. If the
  team wants one, a follow-up research pass on "phased vendor-migration
  patterns for SaaS infrastructure cutover" (not DCV-specific) is needed —
  out of scope here.
- ADR-018 reverses the team's stated "percentage sampling" requirement.
  This needs explicit sign-off before implementation, not silent
  substitution.

## Sources

Primary/authoritative sources backing the confirmed claims above (full list
with per-claim vote counts in the research transcript):

- CA/Browser Forum Baseline Requirements §3.2.2.4.7 (DNS Change method) — https://cabforum.org/working-groups/server/baseline-requirements/requirements/
- RFC 8555 (ACME) — https://www.rfc-editor.org/rfc/rfc8555.html
- Cloudflare for SaaS: Hostname Validation — https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/domain-support/hostname-validation/
- Cloudflare: Validation Backoff Schedule — https://developers.cloudflare.com/ssl/edge-certificates/changing-dcv-method/validation-backoff-schedule/
- Fly.io: Custom Domains — https://fly.io/docs/networking/custom-domain/
- Caddy: Automatic HTTPS (on-demand TLS) — https://caddyserver.com/docs/automatic-https
- Caddy: `on_demand_tls` config reference (`ask` deprecated, `permission` required) — https://caddyserver.com/docs/json/apps/tls/automation/on_demand/ (live API: `GET https://caddyserver.com/api/docs/config/apps/tls/automation/on_demand/`)
- Caddy: `permission.http` module reference (drop-in replacement for `ask`) — https://caddyserver.com/docs/json/apps/tls/automation/on_demand/permission/http/
- Caddy: Caddyfile global options syntax — https://caddyserver.com/docs/caddyfile/options
- OWASP Subdomain Takeover Prevention Cheat Sheet — https://cheatsheetseries.owasp.org/cheatsheets/Subdomain_Takeover_Prevention_Cheat_Sheet.html

## Implementation References

- `lib/onetime/domain_validation/` — strategy.rb, base_strategy.rb, approximated_strategy.rb, approximated_client.rb, passthrough_strategy.rb, caddy_on_demand_strategy.rb
- `lib/onetime/domain_validation/sender_strategies/` — sibling subsystem (sender/email DNS, issue #2835) with in-repo DNS-lookup machinery already built and tested: parallel `Resolv::DNS` lookups with error isolation (`base_strategy.rb#verify_all_records`), strategy-level retry (`with_retry`), Redis-backed DNS rate limiting, and result caching. ADR-016's ownership-axis TXT/CNAME checks should reuse this, not rebuild it. Test-case catalog and edge-case policies (e.g. Redis-unavailable fallbacks) in `docs/test-plans/dns-resilience-2835-qa-plan.md` (stale as a status tracker; designs still sound)
- `lib/onetime/models/custom_domain.rb` — verification state machine, TXT challenge generation
- `lib/onetime/jobs/scheduled/domain_refresh_job.rb` — existing full-sweep re-check job
- `apps/internal/acme/application.rb`, `routes.txt`, `README.md` — Caddy on-demand TLS `ask` endpoint (deprecated form, not yet migrated to `permission`)
- `apps/api/v1/logic/secrets/base_secret_action.rb:456-461` — `validate_domain_verification` gate
- `src/shared/composables/useDomainStatus.ts` — frontend status derivation
- `etc/defaults/config.defaults.yaml:494-537` — config schema (`features.domains` block: strategy, approximated, acme)
- `etc/examples/Caddyfile-example:67-69` — example on-demand TLS config (deprecated `ask` form)
