---
id: "022"
status: proposed
title: "ADR-022: Secret Activity Network-Context Capture Privacy"
---

## Status

Proposed

## Date

2026-07-09

## Context

The org audit trail (`Organization::Features::AuditTrail`, #3633) and the
per-receipt access timeline (`Receipt::Features::AccessTimeline`) record *what*
happened to a secret and *when*, but capture no network context. For org
customers, "from where" is the second question after "who"; a trail with no IP
or user agent cannot answer it.

We want to add network context to the fetch events (`status_get`, `secret_get`,
and the `creator_` / `previewed` variants) without regressing the trail's
privacy posture. That posture is deliberate and already established: the trail
stores **shortids only, never full identifiers**, because a secret identifier
*is* a capability token (it is the link). Network identity is the same class of
problem in a different dimension — a raw IP and a full user-agent string are
directly personal and directly identifying.

Two facts shape the decision:

1. **Prior art.** The auth audit log (`apps/web/auth/config/features/audit_logging.rb`)
   already records `ip` and `user_agent` for login/MFA events, and Otto ships
   the privacy primitives it relies on: `Otto::Privacy::IPPrivacy.mask_ip`
   (zero the last IPv4 octet / last 80 IPv6 bits), `IPPrivacy.hash_ip`
   (keyed HMAC-SHA256), and `RedactedFingerprint#anonymize_user_agent`
   (strip version/build identifiers, truncate).

2. **The raw IP is already gone at the application layer.** Otto's
   `IPPrivacyMiddleware` runs first in the stack and rewrites `REMOTE_ADDR` /
   `otto.client_ip` to the masked IP and scrubs `HTTP_USER_AGENT` to the
   anonymized form before any application code runs. So the values that reach
   the logic layer via the auth `StrategyResult` metadata are, in production,
   already reduced. This is a defense-in-depth property we want to preserve and
   lean on, not bypass.

The plumbing constraint: the org-trail emit happens at the **model** layer
(`Receipt#record_org_audit_event`), which has no request object. The request
context is only available at the **logic** layer, so it must be threaded down.

## Decision

**Store, for each fetch event, three reduced attributes and never the raw
values:**

| Attribute | Representation | Purpose |
|---|---|---|
| `net_ip_partial` | IPv4 last octet zeroed (IPv6 last 80 bits) via `IPPrivacy.mask_ip` | Coarse "from where" — balance of forensics and personal privacy |
| `net_ua_partial` | User agent with version/build identifiers stripped and truncated | Client family without a high-entropy fingerprint |
| `net_ip_hash` | Keyed HMAC-SHA256 over the **partial** IP | Correlation without disclosure |

**The raw dotted-quad IP and the full User-Agent string are never stored,
anywhere in this pipeline.** This mirrors the trail's existing "shortids only,
no capability tokens" rule.

**Capture is centralized and unconditional.** `Onetime::Security::RequestContext`
reads the ip / user-agent from the `StrategyResult` metadata and re-applies the
reduction *every time*, idempotently. Masking an already-masked IP is a no-op;
stripping versions from an already-stripped UA is a no-op. So even if the edge
middleware is disabled or a future change routes a raw value here, the stored
attributes stay masked. The raw IP is touched by exactly one operation
(`mask_ip`) and reduced immediately.

**The correlation hash is keyed by the app's server secret.** We key
`net_ip_hash` with `OT.global_secret` (== `site.secret`), the same root the app
already uses for keyed digests (`Onetime::KeyDerivation`, IncomingConfig
recipient hashing). It is stable across requests, so the same partial IP always
yields the same hash (correlatable across events), while the hash is not
reversible without the secret. We deliberately do **not** use Otto's
daily-rotating hash key, whose rotation would break long-horizon correlation.

**We hash the partial IP, not the raw.** Because the raw IP is architecturally
unavailable at this layer (see Context #2), the hash is computed over the
already-masked IP. It therefore correlates at /24 granularity and provably
cannot encode anything finer than the partial we already store. Its residual
value over the stored partial is as an opaque, fixed-width token that can be
shared or exported without disclosing even the network prefix, and that stays
stable across the trail's lifetime.

**Threading.** `record_access_event(kind, context:)` accepts an optional
string-keyed context hash and forwards it through
`record_org_audit_event(..., **event_attrs)`, which splats it into the org
audit event. Only the fetch/telemetry path supplies it today. The saturation
fan-out guard is unchanged.

## Trade-offs

- **We lose**: full-IP correlation. Two callers in the same /24 are
  indistinguishable in the hash. This is an acceptable and deliberate cost of
  never handling the raw IP.
- **We gain**: a trail that answers "from where" at neighborhood granularity, a
  stable correlation token, and a capture path that is safe by construction —
  it cannot persist raw network data even under misconfiguration.
- **Risk**: the masked IP is low-entropy, so an attacker *holding the server
  secret* could brute-force the /24 behind a hash. Mitigated by the fact that
  the server secret compromising this is the same secret that decrypts every
  stored secret; this hash is not the weak link in that scenario.

## Consequences

- A dedicated no-regression spec asserts that no recorded event attribute ever
  contains a raw dotted-quad IPv4/IPv6 or the full user-agent string — the
  primary safety net against a future change silently persisting raw data.
- Key names are namespaced (`net_`) so this capture composes additively with
  the actor-identity capture (#3639), which shares the same
  `record_org_audit_event(**event_attrs)` seam.

## Implementation Notes

### The /24 correlation granularity is temporary (2026-07-09)

Hashing the *partial* IP (Decision: "We hash the partial IP, not the raw") is a
consequence of the raw IP being architecturally unavailable at this layer, not
a target end state. It yields only /24-granular correlation. This is a **known,
tracked limitation**, not a permanent design choice.

The proper fix lives in Otto: **otto#192** requests that Otto expose a
*stable-keyed* HMAC correlation hash derived from the **full** client IP,
computed inside `IPPrivacyMiddleware` before masking (the one place the full IP
briefly exists), so a consumer can get per-host correlation without ever
handling the raw IP. Otto already computes a full-IP hash (`otto.privacy.hashed_ip`),
but it is keyed with a **daily-rotating** key — unusable for a long-lived audit
trail — which is why this ADR fell back to hashing the masked IP with a stable
app secret.

When otto#192 lands: switch `net_ip_hash` to consume Otto's stable full-IP
correlation hash, upgrading correlation from /24 to per-host, with no change to
this pipeline's "raw IP never reaches app code" invariant. Until then, the /24
granularity stands and is documented inline at the hash site
(`lib/onetime/security/request_context.rb`).

## Cross-references

- Ticket #3640 (this work); event-side capture umbrella #3633 / PR #3635.
- ADR-021 (audit-log stream terminology / scoping) — naming of the stream this
  data lands in.
- Sibling capture: #3639 (actor identity on revealed/burned), same
  `record_org_audit_event` extension point.
- Upstream follow-up: otto#192 (stable-keyed full-IP correlation hash) — see
  Implementation Notes; unblocks per-host correlation.
- Upstream follow-up: otto#194 (public UA-anonymization surface) — lets
  `RequestContext.mask_user_agent` delegate instead of copying Otto's private
  version/build-stripping regexes; a cross-implementation spec guards the drift
  until it lands.
- ADR-023 (audit actor attribution accuracy) — never fabricate an actor; record
  an explicit `unknown` when attribution is indeterminate. Same shortids-only,
  minimized posture applied to the actor dimension.
