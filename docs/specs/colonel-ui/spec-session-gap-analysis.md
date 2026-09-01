# docs/specs/colonel-ui/spec-session-gap-analysis.md

## created: 2026-07-29

Itemized gap analysis of `spec-session-expectations.md` against the code on
`main` at `5d952a6fc`. Fourth doc in the set:

- `spec-session-expectations.md` — what a super-admin session feature should do
- **this doc** — the full itemization, section by section
- `spec-session-path.md` — is there a path? (yes; §4 already lists four gaps)
- `spec-session-performance.md` — why the console is slow

**How to read it.** Rows follow the expectations doc's own section order, not
severity order. Priority is a tag on each row, deliberately not a ranking — a P0
in §1 is not "the top of the list", it is a P0 that happens to live in §1.

- **P0** — security defect or compliance blocker; fix before feature work
- **P1** — required for the stated compliance posture, or a real operator gap
- **P2** — real gap, deferrable
- **N/A** — the requirement presumes architecture this system does not have;
  listed so it stops re-appearing as a gap
- **KNOWN** — already itemized in `spec-session-path.md` §4/§5; not re-derived

Where this doc corrects a sibling spec, see §10.

**The precondition is met.** The expectations doc opens by saying authoritative
server-side revocation determines whether anything else is possible. Sessions die
by `DEL session:<sid>` (`lib/onetime/session.rb:151`), not by expiring a
stateless token. `spec-session-path.md` §4 establishes this and it holds. What
follows is incremental work, not architectural work — with two exceptions (1.6
and 3.1) that are architectural in the sense that no amount of UI fixes them.

Read that precisely, because the short form ("sessions die by `DEL`, not by
expiry") is wrong in a way that matters. The blob key _does_ carry a TTL
(`default_expiration: @expire_after`, `session.rb:146`), and an abandoned session
is gone in 24 h. The contrast is about where revocation _authority_ lives — a
server record rather than a self-verifying credential — not about whether an
expiry exists. A TTL cannot be either thing the expectations doc needs it to be:
it is **not a revocation lever** (you cannot make a TTL happen now; the nearest
operation, `EXPIRE 0`, _is_ `DEL`), and it is **not a lifetime** (`write_session`
refreshes it on every write, `:697`, and that write commits roughly per request,
`:709`, so activity resets the clock). Accurately: **sessions die by `DEL` on
demand, or after 24 h of inactivity — never of age.** The third clause is 3.2.

---

## 1. Inventory and visibility

| #    | Requirement                                                 | Current state                                                                                                                                                          | Gap                                                                                                                                           | Pri      |
| ---- | ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| 1.1  | Filter by user                                              | Global: free-text over email/extid (`store.rb:212`). Per-customer: exact, indexed (`list_for_customer.rb`)                                                             | None                                                                                                                                          | ✓        |
| 1.2  | Filter by tenant                                            | `SessionMetadata#org_id` is populated (`session_metadata.rb:70`) and surfaced by neither list                                                                          | Wire the existing field                                                                                                                       | P2 KNOWN |
| 1.3  | Filter by IP                                                | Stored per session, masked to /24–/48 by the universal `IPPrivacyMiddleware` mount (`middleware_stack.rb:296`)                                                         | Filterable by prefix only. Label it as prefix-precision in the UI rather than implying host precision                                         | P2 KNOWN |
| 1.4  | Filter by geo/ASN                                           | **Country**: `SessionMetadata#geo_country` now populated from `env['otto.privacy.geo_country']` (otto 2.8 `Otto::Privacy::GeoResolver`; resolved from a trusted CDN header — e.g. Cloudflare `CF-IPCountry` — or a masked-IP MMDB lookup, `'**'` when unknown). **ASN**: no ASN dependency anywhere; otto has no ASN support | **Country is now buildable** — masking does not block it, the raw IP is never needed (see `geo-precision-profile-evaluation.md`). Wire the existing sidecar field into the filter. **ASN stays won't-build**, unchanged — nothing to reverse a posture for; otto resolves country only (§5 of `spec-session-path.md` still governs the ASN half) | P2 (country) / N/A (ASN) |
| 1.5  | Filter by device fingerprint/UA                             | UA stored, masked; no fingerprint                                                                                                                                      | Same posture decision as 1.4                                                                                                                  | N/A      |
| 1.6  | **Opaque session ID — never the raw token or cookie value** | The admin renders the live cookie value verbatim                                                                                                                       | **See 1.6 detail below**                                                                                                                      | **P0**   |
| 1.7  | Filter by auth method                                       | `auth_method` populated at login (`session_metadata.rb:76`), unused by both lists                                                                                      | Wire the existing field                                                                                                                       | P2 KNOWN |
| 1.8  | Filter by created-at / last-seen / expires-at               | `created_at` + `last_activity_at` in the sidecar; global list sorts by `authenticated_at` but exposes no range filter; `expires_at` is not stored (it is the blob TTL) | Add range filters; derive `expires_at` from the TTL probe `ListForCustomer` already does                                                      | P2       |
| 1.9  | MFA satisfied y/n + factor type                             | `mfa_used` field exists and `TrackMetadata` returns `nil` unconditionally                                                                                              | Stamp at auth time, mirroring `auth_method` in `hooks/login.rb`. Factor type needs a second field (`otp` / `recovery_code` / `webauthn`)      | P1 KNOWN |
| 1.10 | IdP subject                                                 | `auth_method` records the string `'omniauth'` with no provider and no subject                                                                                          | Cannot answer "which IdP, which subject" — the question an SSO incident starts with. Add `idp_provider` + `idp_subject`                       | P1       |
| 1.11 | Elevation / sudo state                                      | No such concept in the codebase                                                                                                                                        | Blocked on 3.3                                                                                                                                | P1       |
| 1.12 | Impersonation flag                                          | No such concept                                                                                                                                                        | Blocked on §4                                                                                                                                 | P2 KNOWN |
| 1.13 | Concurrent session count per identity                       | `Customer#active_sessions` ZSET exists; `ZCARD` not surfaced                                                                                                           | One-line addition                                                                                                                             | P2 KNOWN |
| 1.14 | Refresh-token family lineage                                | No refresh tokens; sessions are server-side blobs                                                                                                                      | Requirement does not apply                                                                                                                    | N/A      |
| 1.15 | Global inventory is capped and slow                         | `Sessions::List` scans + decrypts the keyspace, capped at `MAX_SCAN = 10_000`; count reports exactly 10,000 forever                                                    | The whole subject of `spec-session-performance.md` and §1–§3 of `spec-session-path.md`                                                        | KNOWN    |

### 1.6 detail — the session ID in the console is a live credential

Verified chain:

1. The store keys on `public_id`: `get_stringkey(sid)` → `session:<public_id>`
   (`session.rb:143`), with the same extraction at `152`, `389`, `592`.
2. `public_id` is the cookie value. `session.rb:589` states it: _"Cookie contains
   just the session ID (not encrypted) — Set-Cookie: onetime.session=c9803eb…"_.
   Verified live against the running app: `onetime.session=9ce0900f…; path=/;
secure; httponly; samesite=lax`.
3. `find_session` accepts any format-valid sid — `valid_session_id?` only
   (`session.rb:399`). No IP binding, no UA binding, no cookie signature beyond
   the sid itself.
4. `BaseSessionAuthStrategy` then needs only `session['authenticated'] == true`
   plus a loadable, unsuspended customer
   (`base_session_auth_strategy.rb:41–58`).
5. The admin renders it: `AdminSessions.vue:349` (`{{ row.session_id }}` in a
   monospace column), the drawer title at `423`, the detail field at `198`, and
   the same value in `AdminCustomerSessionsSection.vue`.

So: read the console, copy a row's session ID into an `onetime.session` cookie,
and you are that user — with no impersonation record, no audit event, and no
banner. This is the expectations doc's stated anti-requirement ("Don't render raw
tokens in the admin UI") and it defeats every impersonation control §4 asks for
before those controls are even built.

Note `revoke_for_customer.rb:103` — _"session_id is a public identifier"_ — which
institutionalizes the misconception. The comment is the thing to fix first,
because it is what makes the rest look acceptable.

Scope of exposure: the console is `role=colonel` only, so this is not an
anonymous-attacker path. It matters because it (a) converts a read-only view into
an un-audited identity assumption, (b) puts live bearer material into every
surface that captures an API response — screenshots, devtools, proxy logs, error
reporting breadcrumbs — and (c) blocks any future lower-privileged support role
from ever being given session read.

Fix: display `HMAC(sid)` truncated, or an opaque per-session display id stored on
the sidecar; accept the plain sid only as _input_ to revoke. `SessionMetadata`
already exists as the natural home for a display id. Audit rows should carry the
hashed form (see 5.7).

**Resolved for the global console (#4330).** `Sessions::List` now emits
`SessionMetadata.handle_for(sid)` and strips `session_id`/`key` unless the caller
passes `reveal_session_id: true` (only `bin/ots session` does).
`GET`/`DELETE /api/colonel/sessions/:session_handle` take the handle and resolve
it server-side via `Sessions::Store.resolve_handle` — owner-hinted first, bounded
scan second — and `Sessions::Delete` records the handle as its audit target. The
console renders a truncated handle and gates revoke on the session owner's email.
Still open here: the raw sid inside `RevokeForCustomer`'s audit **detail** (its
`target` is the customer), and the "session_id is a public identifier" comment at
`revoke_for_customer.rb:103`.

---

## 2. Termination

| #    | Requirement                                        | Current state                                                                                                                                                                                                                                                                                                          | Gap                                                                                                                                                                                                                                                                                                                                                                                   | Pri      |
| ---- | -------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| 2.1  | Revoke one session                                 | `DELETE /sessions/:id` (global) and `DELETE /users/:id/sessions/:sid` (per-customer)                                                                                                                                                                                                                                   | None                                                                                                                                                                                                                                                                                                                                                                                  | ✓        |
| 2.2  | Revoke all for a user                              | `RevokeAllForCustomer` — two-tier: exact uncapped kill over `active_sessions`, then a best-effort untracked sweep, then Rodauth `account_active_session_keys`                                                                                                                                                          | None                                                                                                                                                                                                                                                                                                                                                                                  | ✓        |
| 2.3  | Revoke all for a tenant                            | No op, no route. `org_id` is on the sidecar                                                                                                                                                                                                                                                                            | Compose over the existing field                                                                                                                                                                                                                                                                                                                                                       | P2 KNOWN |
| 2.4  | Global break-glass revoke                          | Primitives exist; nothing composes them                                                                                                                                                                                                                                                                                | Compose                                                                                                                                                                                                                                                                                                                                                                               | P2 KNOWN |
| 2.5  | **Cascade: remember-me**                           | `remember` feature enabled (`features/remember_me.rb:13`), `account_remember_keys` table exists (`migrations/001_initial.rb:108`), and **no revoke path references it**                                                                                                                                                | **See 2.5 detail**                                                                                                                                                                                                                                                                                                                                                                    | P1 KNOWN |
| 2.6  | Cascade: refresh tokens                            | None exist                                                                                                                                                                                                                                                                                                             | N/A                                                                                                                                                                                                                                                                                                                                                                                   | N/A      |
| 2.7  | Cascade: OAuth/PAT grants issued under the session | No PAT or session-derived-grant concept                                                                                                                                                                                                                                                                                | N/A                                                                                                                                                                                                                                                                                                                                                                                   | N/A      |
| 2.8  | Cascade: WebSocket/SSE                             | None                                                                                                                                                                                                                                                                                                                   | N/A                                                                                                                                                                                                                                                                                                                                                                                   | N/A      |
| 2.9  | Cascade: sidecar keys + index                      | `delete_session` purges `SessionSidecar` keys (`session.rb:170+`); `RevokeAllForCustomer` destroys `SessionMetadata` and ZREMs the index                                                                                                                                                                               | None                                                                                                                                                                                                                                                                                                                                                                                  | ✓        |
| 2.10 | Auto-revoke on password change                     | `after_change_password` + `after_reset_password` revoke in-transaction, with a credential watermark and an async `SessionRevocationSweepWorker` (#3810)                                                                                                                                                                | None                                                                                                                                                                                                                                                                                                                                                                                  | ✓        |
| 2.11 | Auto-revoke on MFA enrollment change               | `hooks/mfa.rb` has no revoke on `after_otp_setup` / `after_otp_disable`                                                                                                                                                                                                                                                | Add both. Disabling MFA is a credential-strength downgrade and should not leave pre-existing sessions alive                                                                                                                                                                                                                                                                           | P1       |
| 2.12 | Auto-revoke on role/permission change              | `set_role.rb` does not revoke — **and does not need to.** Authorization re-reads the live record every request: `SessionAuthStrategy` loads the customer fresh (`base_session_auth_strategy.rb:51`) and `has_system_role?` reads `cust.role` (`authorization_policies.rb:52–64`). A demotion binds on the next request | Residual is cosmetic only: the blob still carries `role`, so `Store.summarize` can show a stale role in the console. Hydrate from the customer record                                                                                                                                                                                                                                 | P2       |
| 2.13 | Auto-revoke on deactivation                        | `SetSuspension` sweeps the keyspace for the customer's sessions and audits it; and `BaseSessionAuthStrategy` rejects suspended accounts every request                                                                                                                                                                  | None                                                                                                                                                                                                                                                                                                                                                                                  | ✓        |
| 2.14 | Auto-revoke on account deletion                    | `PurgeUser` → `DeleteCustomer` destroys the customer and its sub-keys; **no session sweep** (`delete_customer.rb:81–87`)                                                                                                                                                                                               | Sessions go inert on the next request (`[CUSTOMER_NOT_FOUND]`, `base_session_auth_strategy.rb:52`), so the anti-requirement is honoured _behaviourally_, by fail-closed lookup rather than by revocation. But blobs, sidecars, and the `active_sessions` ZSET survive to TTL, so the console keeps listing sessions for a deleted account. Call `RevokeAllForCustomer` before destroy | P1       |
| 2.15 | CLI revoke path                                    | `bin/ots session` = `inspect` / `list` / `search` / `delete` / `clean`. `delete` is one sid at a time                                                                                                                                                                                                                  | **No per-user revoke-all in the CLI.** The documented break-glass ("when the web UI is unreachable") is per-sid, or `bin/ots customers suspend` as a side effect. Add `bin/ots session revoke-all --user` over the existing op                                                                                                                                                        | P1       |
| 2.16 | `session clean` does nothing                       | Its only `del` branch is `ttl == 0` (`session_command.rb:381–393`), which Redis never reports — expired keys are already gone                                                                                                                                                                                          | Dead command that reports "Expired sessions removed: 0" and looks like it worked. Delete it or repurpose it to prune orphaned sidecars and stale index members                                                                                                                                                                                                                        | P2       |

### 2.5 detail — the remember-me cascade, and why it is latent

`spec-session-path.md` §4 correctly calls this the most important gap and the
exact failure mode the expectations doc names ("partial revocation is the most
common real-world bug"). One fact to add, verified: **`load_memory` is never
called anywhere in `apps/` or `lib/`.** The only mention of remember at all
outside the feature config is a Rodauth-internal default.

Two consequences, and the fix order depends on both:

- The revocation gap is **latent, not live**: nothing currently consumes a
  remember cookie, so a revoked session cannot be re-minted from one today.
- "Remember me" **does not work**: the feature issues cookies and writes
  `account_remember_keys` rows that nothing ever reads.

Wiring `load_memory` — the natural next step for anyone making the feature
work — converts the latent gap into a live revocation bypass in one line. Fix
the cascade in the same change, or disable the feature until the cascade
exists. Do not ship the wiring alone.

---

## 3. Policy

| #    | Requirement                                                      | Current state                                                                                                                                                                                                                         | Gap                                                                                                                                                                                                                                                                                                                                                            | Pri      |
| ---- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| 3.1  | Idle timeout                                                     | `expire_after: 86400`, refreshed via `update_expiration` on **every** write (`session.rb:696`)                                                                                                                                        | 24h rolling idle. Not configurable independently. Out of range for every framework the expectations doc cites                                                                                                                                                                                                                                                  | **P0**   |
| 3.2  | Absolute lifetime                                                | **None on the request path.** See 3.1/3.2 detail                                                                                                                                                                                      | **P0**                                                                                                                                                                                                                                                                                                                                                         |
| 3.3  | Step-up / sudo re-auth window                                    | Nothing. No re-auth anywhere in the colonel ops                                                                                                                                                                                       | Destructive colonel ops gate on typed-extid confirm dialogs (UI-only) and `dry_run` defaults. Neither is a re-auth. Blocks 1.11                                                                                                                                                                                                                                | P1       |
| 3.4  | Remember-me max duration                                         | Rodauth default 14d, inherited, not exposed in OTS config (`features/remember_me.rb:16`)                                                                                                                                              | Surface as config                                                                                                                                                                                                                                                                                                                                              | P2       |
| 3.5  | Max concurrent sessions + overflow behavior                      | Absent entirely — no cap, no deny-new, no evict-oldest                                                                                                                                                                                | Absent                                                                                                                                                                                                                                                                                                                                                         | P2 KNOWN |
| 3.6  | Cookie hardening as config                                       | Verified live: `path=/; secure; httponly; samesite=lax`. `secure` defaults true in production (`boot.rb:343` + `ssl_enabled?`); `same_site: lax` is configured; a dropped-secure-cookie warning exists (`session.rb:261–271`)         | Substantially met                                                                                                                                                                                                                                                                                                                                              | ✓        |
| 3.7  | `__Host-` prefix                                                 | Cookie is `onetime.session`                                                                                                                                                                                                           | Adoptable: the attributes `__Host-` requires (`Secure`, `path=/`, no `Domain`) are already what is emitted. Rename behind a config flag with a migration note — the rename logs everyone out                                                                                                                                                                   | P2       |
| 3.8  | Domain scoping as config                                         | Not configurable                                                                                                                                                                                                                      | Add alongside 3.7                                                                                                                                                                                                                                                                                                                                              | P2       |
| 3.9  | `httponly` config key is inert                                   | Present in `config.defaults.yaml:347` and `SESSION_DEFAULTS` (`boot.rb:84`) but **never passed** to the middleware — `middleware_stack.rb:343–350` passes only secret/expire_after/key/secure/same_site                               | Behavior is correct (HttpOnly comes from Rack's inherited default), but the knob does nothing and the config comment "always true in Rack" is what makes that invisible. Wire it or delete it                                                                                                                                                                  | P1       |
| 3.10 | `DEFAULT_OPTIONS` block is dead code                             | `unless defined?(DEFAULT_OPTIONS)` (`session.rb:62`) matches the **inherited** `Rack::Session::Abstract::Persisted::DEFAULT_OPTIONS`, so the block never executes and `Onetime::Session::DEFAULT_OPTIONS` _is_ Rack's hash (verified) | Harmless today — `key`/`expire_after` are passed explicitly, `namespace` has a fallback, and Rack's `sidbits: 128` still yields `SecureRandom.hex(32)` = 64-hex/256-bit sids. But the file documents defaults that are not in effect, including a `sidbits: 256` that never applies. A live trap for the next editor                                           | P1       |
| 3.11 | Session ID rotation on privilege elevation                       | Rotation on **login** works: `clear_session` → `session.destroy` (`base.rb:89–91`), plus `rack.session.options[:renew]` at authentication (`authentication.rb:51`, `session_helpers.rb:54`, `account.rb:854`)                         | Fixation defense on login: present but **conditional**, not guaranteed — all three call sites guard on `rack.session.options` being available, and `account.rb:876–884` logs `security_warning: 'rack.session.options missing; session id not rotated'`, a branch that exists because it was reached. Rotation on elevation: no elevation concept exists (3.3) | P1       |
| 3.12 | Per-role and per-tenant policy overrides                         | None                                                                                                                                                                                                                                  | Absent                                                                                                                                                                                                                                                                                                                                                         | P2 KNOWN |
| 3.13 | Admin sessions strictly shorter than user sessions               | Same single `onetime.session` cookie, same `expire_after`, for colonel and tenant alike                                                                                                                                               | Absent                                                                                                                                                                                                                                                                                                                                                         | P1       |
| 3.14 | Admin session must not share a cookie with the tenant-facing app | It does — one cookie name, one store, one TTL                                                                                                                                                                                         | Compensating control exists (`AdminNetworkIsolation` middleware). Not a substitute: a stolen tenant-app session cookie from a colonel's browser is a colonel session                                                                                                                                                                                           | P1       |

### 3.1/3.2 detail — two policy engines, neither covering the request path

There are two independent session-policy mechanisms with non-overlapping
enforcement surfaces:

- **The blob path** (`Onetime::Session`) validates every request in every mode.
  Its only policy is `expire_after`, refreshed on each write — a _rolling idle_
  window. There is **no absolute lifetime cap at all**: a session touched daily
  lives forever.
- **Rodauth `active_sessions`** has both knobs — `session_inactivity_deadline
86_400` and `session_lifetime_deadline 2_592_000`
  (`features/active_sessions.rb:20–21`) — but `account_active_session_keys` only
  gates Rodauth-mounted routes, in `full` mode. The codebase says so:
  `session_metadata.rb:25–27`.

So the surface that actually authenticates every request has idle-only policy at
24h, and the surface with a 30-day absolute cap does not gate the general request
path. Do not score "idle timeout: present" — score it out of range and name the
split. Concretely against §7: 24h rolling idle vs AAL2's 30 min, AAL3's 15 min,
PCI's 15 min; and no absolute lifetime vs AAL2's 12h reauth.

The fix is one enforcement point on the blob path: store `authenticated_at`
(already in the session data) and `last_activity_at` (already on the sidecar),
and reject in `find_session` on either bound, with both bounds configurable.
That single change moves 3.1, 3.2, 7.1, 7.2 and 7.3 together.

---

## 4. Impersonation

Not implemented. The spike (`initial-build-out/52-impersonation-audit-fix.md`)
confirmed the _suspected_ implicit path was absent — a dead
`@colonel&.passphrase?` clause, since removed — and no explicit operation was
built in its place. Three files mention impersonation; none implement it.

| #    | Requirement                                                             | Pri      |
| ---- | ----------------------------------------------------------------------- | -------- |
| 4.1  | First-class separate session type                                       | P2 KNOWN |
| 4.2  | Required reason field                                                   | P2 KNOWN |
| 4.3  | Time-boxed                                                              | P2 KNOWN |
| 4.4  | Non-nestable                                                            | P2 KNOWN |
| 4.5  | Separately revocable                                                    | P2 KNOWN |
| 4.6  | Optional read-only mode                                                 | P2 KNOWN |
| 4.7  | Visible banner                                                          | P2 KNOWN |
| 4.8  | Dual attribution (real admin _and_ target) in the audit log             | P2 KNOWN |
| 4.9  | Cannot target other super admins                                        | P2 KNOWN |
| 4.10 | Configurable notification to the impersonated user / their tenant admin | P2       |

Ordering note: 1.6 is a prerequisite, not a parallel task. While the console
hands out live cookie values, an impersonation feature with a reason field and a
banner is a control that can be trivially bypassed by the same operator it
constrains — the audit trail would record only the operators who chose to use it.

---

## 5. Audit

`ColonelAuditEvent` (formerly `AdminAuditEvent`; renamed in #3977) is a Redis
sorted set of `{actor, verb, target, result, detail,
created, id}` with sensitive-key redaction on `detail`
(`models/colonel_audit_event.rb`).

| #    | Requirement                                         | Current state                                                                                                                                                                             | Gap                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Pri |
| ---- | --------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --- |
| 5.1  | Append-only                                         | No update path; writes are ZADD-only                                                                                                                                                      | Met in practice                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | ✓   |
| 5.2  | Tamper-evident                                      | No hash chain, no signature, no sequence number. Any member is `ZREM`-able by anything holding the Redis connection                                                                       | The SOC 2 / ISO evidence requirement is specifically for tamper-_evidence_, not append-only-by-convention. Add a per-event chained digest over the previous event                                                                                                                                                                                                                                                                                                                                                                                                 | P1  |
| 5.3  | Exportable to syslog/SIEM/webhook                   | No sink of any kind. `GET /api/colonel/audit` + the UI are the only readers                                                                                                               | This is the row that makes 5.2 and 5.4 tolerable if it lands first: an external sink is both the retention answer and the tamper-evidence answer                                                                                                                                                                                                                                                                                                                                                                                                                  | P1  |
| 5.4  | Configurable retention                              | `MAX_EVENTS = 10_000` hard constant, trimmed on **every** write, no TTL (`colonel_audit_event.rb:116`, `274–279`)                                                                            | Self-hosted operators own the retention obligation and cannot set it. Structurally, a count cap with no time floor is an eviction primitive: 10k events of routine activity silently drop the oldest evidence, and the retention window is whatever the event rate happens to be. **How long 10k buys is unmeasured** — dev holds 2 events, which says nothing. Measure before sizing anything: `ZCARD colonel_audit_event:events` plus the oldest and newest scores (`ZRANGE … 0 0 WITHSCORES` / `-1 -1 WITHSCORES`) on production gives the current span directly | P1  |
| 5.5  | Audit session **create**                            | Not audited — `Sessions::List` documents the policy: "audit is for mutations" (CONTRACT 4)                                                                                                | Session creation is the event a compliance auditor asks to see first. It also belongs on a different sink than admin mutations — anonymous session churn dominates the keyspace and would blow the 10k cap in minutes. Route it to 5.3, not to `ColonelAuditEvent`                                                                                                                                                                                                                                                                                                  | P1  |
| 5.6  | Audit session renew / expire                        | Neither. Expiry is a Redis TTL with no event                                                                                                                                              | Same routing as 5.5                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | P2  |
| 5.7  | Audit session revoke, with actor **and reason**     | Actor ✓. **Reason: nowhere.** No revoke op or route accepts one (`grep reason lib/onetime/operations/sessions/` → nothing)                                                                | Add a required reason on every revoke surface — console, CLI, ops layer                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | P1  |
| 5.8  | Hash session identifiers; never log bearer material | `delete_session.rb:77` puts the plain sid in `target`; `revoke_for_customer.rb:112` puts it in `detail`; `session.rb:155` logs it at **info** level on delete, and at trace on read/write | The audit rows are written _after_ the blob is deleted, so the stored value is dead-on-arrival — real but bounded. The `info`-level log line is not so bounded. Hash on the way in; the comment at `revoke_for_customer.rb:103` asserting the sid "is a public identifier" is the root cause and should go with it                                                                                                                                                                                                                                                | P1  |
| 5.9  | Audit impersonation start/stop                      | Nothing to audit yet (§4)                                                                                                                                                                 | Blocked                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | P2  |
| 5.10 | Audit policy change                                 | No policy to change (§3)                                                                                                                                                                  | Blocked on 3.1/3.2                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | P2  |
| 5.11 | Audit failed auth and lockout                       | Rodauth's own `audit_logging` feature covers these into the auth DB (`features/audit_logging.rb:280–300`), plus `OT.le`                                                                   | Two disjoint audit stores. The colonel audit view cannot show a lockout or a failed login, so the console cannot answer "what happened to this account" from one place. Unify at the 5.3 sink                                                                                                                                                                                                                                                                                                                                                                     | P1  |
| 5.12 | Audit writes are fail-open                          | `record` swallows every error (`colonel_audit_event.rb:181–196`); the fail-closed HOOK for destructive verbs is explicitly deferred                                                         | A destructive op can complete with no audit row and no signal. Take the deferred hook for `purge`, `revoke_all`, and impersonation                                                                                                                                                                                                                                                                                                                                                                                                                                | P1  |

---

## 6. Detection

| #   | Requirement                                        | Current state                                                                                                                    | Gap                                                                                                                                                                         | Pri      |
| --- | -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| 6.1 | Impossible travel                                  | Country-level geo now available — `SessionMetadata#geo_country` (otto 2.8 `GeoResolver`), `'**'` when unresolved. No device fingerprint                                        | The "no geolocation of any kind" premise no longer holds, and the raw-prefix objection does not apply — country is resolved from a trusted CDN header or a masked-IP MMDB lookup, never derived from the masked /24–/48 prefix (see `geo-precision-profile-evaluation.md`). Impossible travel at **country** granularity is coarse, not impossible — but VPNs/roaming/CDN egress make it a noisy signal, so keep the recommendation conservative: this is a design decision to evaluate, not an auto-enabled default. See `geo-precision-profile-evaluation.md` | P2 |
| 6.2 | New device / geo                                   | **Geo**: available at country granularity, same path as 6.1. **Device**: no fingerprint                                                                                          | **Geo half no longer N/A** — a "new country for this account" signal is buildable at that granularity, same caveats as 6.1 (see `geo-precision-profile-evaluation.md`). **Device-fingerprint half stays N/A** — no fingerprint collected, same posture as 1.5 | P2 (geo) / N/A (device) |
| 6.3 | Refresh-token replay auto-revoking the family      | No refresh tokens                                                                                                                | N/A                                                                                                                                                                         | N/A      |
| 6.4 | Simultaneous sessions from disparate ASNs          | No ASN data                                                                                                                      | Degraded form is buildable: simultaneous sessions from disparate /24s. Worth having; weaker than the requirement                                                            | P2       |
| 6.5 | Lockout state visible                              | Rodauth `lockout` is enabled with `max_invalid_logins 5` (`features/lockout.rb:15`). No colonel surface reads `account_lockouts` | Support cannot see why a customer is locked out                                                                                                                             | P1       |
| 6.6 | Lockout manually resettable                        | No unlock op in the colonel or the CLI. `POST /ratelimit/reset` resets OTS rate limiters, **not** Rodauth lockouts               | Direct support-load item. Add an audited unlock op                                                                                                                          | P1       |
| 6.7 | One-click quarantine (disable + revoke everything) | Suspension already revokes and audits (2.13)                                                                                     | UI composition over an existing op                                                                                                                                          | P2 KNOWN |

---

## 7. Compliance mapping

Nothing in the docs names any of these frameworks. Each row below is both a
concrete gap and the doc text that should exist.

| #   | Framework                 | Requirement                                                                                         | Current                                                                                                                                                                                                                                                                                                                                                                                     | Pri    |
| --- | ------------------------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| 7.1 | NIST SP 800-63B AAL2      | 30 min idle / 12 h absolute reauth                                                                  | 24 h rolling idle; no absolute cap on the request path (3.1/3.2)                                                                                                                                                                                                                                                                                                                            | **P0** |
| 7.2 | NIST SP 800-63B AAL3      | 15 min idle                                                                                         | Same                                                                                                                                                                                                                                                                                                                                                                                        | P1     |
| 7.3 | PCI DSS 4.0 §8.6.x        | 15 min idle                                                                                         | Same                                                                                                                                                                                                                                                                                                                                                                                        | P1     |
| 7.4 | HIPAA §164.312(a)(2)(iii) | Automatic logoff                                                                                    | A 24 h rolling window is not meaningfully automatic logoff                                                                                                                                                                                                                                                                                                                                  | P1     |
| 7.5 | SOC 2 CC6.1 / CC6.6       | Revocation capability + audit evidence                                                              | Revocation ✓. Evidence ◐ — no export (5.3), no tamper-evidence (5.2), 10k count cap (5.4)                                                                                                                                                                                                                                                                                                   | P1     |
| 7.6 | ISO 27001 A.5.15–A.5.18   | Same                                                                                                | Same                                                                                                                                                                                                                                                                                                                                                                                        | P1     |
| 7.7 | GDPR                      | Session records are personal data → retention limits, subject-access inclusion, deletion on erasure | IP and UA are **masked** at ingress (/24–/48, `IPPrivacyMiddleware`), which materially reduces but does not eliminate this. Retention is whatever the TTLs are (blob 24 h rolling, `SessionMetadata` 30 d) with no configuration; **no subject-access export exists**, so sessions are in none; and no erasure path removes them — `DeleteCustomer` leaves blobs and sidecars behind (2.14) | P1     |

---

## 8. Self-hosted specifics

| #   | Requirement                                          | Current state                                                                                                                                                                                                                                                                                                                                      | Gap                                                                                                                                                                                                                                                                                                                                                                                                                                    | Pri |
| --- | ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --- |
| 8.1 | Trusted proxy configuration                          | Fully built and better than the expectations doc assumes: `site.network.trusted_proxy` with `enabled` / `header` / `depth` / `filter` modes, resolved once into `env['otto.client_ip']` by a universal `IPPrivacyMiddleware` mount, prompted by `config_generator.rb:106`, with a deprecation shim for the old per-homepage knob (`config.rb:194`) | **Default OFF**: `enabled: <%= ENV['TRUSTED_PROXY_ENABLED'] == 'true' %>` (`config.defaults.yaml:428`). So the exact failure the report describes — every session row and audit entry reading the ingress hop — _is_ the out-of-box state behind any reverse proxy. `middleware_stack.rb:283–288` documents the consequence. Fix: warn at boot when a forwarded header is present on real traffic and `trusted_proxy.enabled` is false | P1  |
| 8.2 | Document what key rotation does to existing sessions | `docs/runbooks/secret-rotation.md:11` lists `SESSION_SECRET` and says nothing about sessions                                                                                                                                                                                                                                                       | Rotating it fails the HMAC on every stored blob → `find_session` mints a new empty session → **mass silent logout of every user**. Operators must know before they rotate, not after. Docs-only, cheap, high consequence                                                                                                                                                                                                               | P1  |
| 8.3 | Version the session serialization format             | No version marker. The format is `base64(iv+tag+ct)--hmac` (`codec.rb:11–13`)                                                                                                                                                                                                                                                                      | The only compatibility mechanism is `Store.load_data`'s read-side fallback chain (codec → legacy JSON → `_raw`), which is exactly the drift that produced the "every session shows Anonymous" incident. A one-byte version prefix makes the next format change a migration instead of an outage                                                                                                                                        | P2  |
| 8.4 | No external network call for revocation              | Redis/Valkey + Postgres only                                                                                                                                                                                                                                                                                                                       | Air-gapped safe                                                                                                                                                                                                                                                                                                                                                                                                                        | ✓   |

---

## 9. Anti-requirements

| #   | Anti-requirement                                      | Verdict                                                                                                                                                                                                                        |
| --- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 9.1 | Don't render raw tokens in the admin UI               | **VIOLATED** — 1.6                                                                                                                                                                                                             |
| 9.2 | Don't implement logout as a client-side cookie delete | Not violated. `clear_session` → `session.destroy` → `delete_session` DELs the blob server-side (`base.rb:89–91`, `session.rb:151`)                                                                                             |
| 9.3 | Don't ship a "delete user" that leaves sessions live  | Not violated _behaviourally_ — the fresh customer read fails closed on the next request. But the mechanism is incidental, not intentional: no sweep runs, and the blobs, sidecars and index entries outlive the account (2.14) |

---

## 10. Corrections and additions to `spec-session-path.md`

That doc's §4 is the right conclusion — the expectations half is incremental, not
architectural — and its four named gaps all hold. Five amendments:

1. **§4 "the anti-requirement ('don't ship a delete-user that leaves sessions
   live') is already honoured"** cites `set_user_suspension.rb`. Suspension is
   not deletion. The delete path (`PurgeUser` → `DeleteCustomer`) runs no sweep;
   the anti-requirement survives on the auth strategy's fail-closed customer
   lookup, not on revocation. See 2.14.
2. **§4 "A CLI path exists (`bin/ots session`)"** — it has `delete` for one sid,
   not revoke-all. The break-glass path the expectations doc asks for is not
   there. See 2.15.
3. **§4 omits 1.6.** The console renders live cookie values. It outranks the
   remember-me cascade and it is a prerequisite for §4's impersonation work.
4. **§4's remember-me finding gains one fact**: `load_memory` is never called, so
   the gap is latent and remember-me is non-functional today. That changes the
   fix from "add a cascade" to "add the cascade and the wiring together, or
   disable the feature". See 2.5.
5. **§5's IP-masking premise holds** — verified: `IPPrivacyMiddleware` is mounted
   universally and rewrites `env['REMOTE_ADDR']` to the masked client IP before
   any downstream consumer, so `@session['ip_address'] = @request.ip`
   (`sync_session.rb:327`) stores a masked value despite reading a raw-looking
   accessor. Worth stating explicitly, because the `SessionMetadata` docstring's
   "already masked upstream by Otto" claim is not verifiable from that file and
   invites a well-meaning "fix".

**On §6's suggested order.** It sequences remember-me → global index → counts →
anonymous minting → policy → impersonation. Two changes:

- Put **1.6** (mask the session ID in the console) first. It is small, it is a
  live credential exposure, and it gates the impersonation work at the end of
  the list.
- Put **3.1/3.2** (idle + absolute lifetime on the blob path) at position 2 if
  compliance is driving, rather than at 5. It is the single change that moves
  five compliance rows at once, and it is independent of the index work.

---

## Summary counts

85 requirement rows across §1–§8, plus 3 anti-requirement verdicts in §9:
**9 met**, **9 not applicable**, **67 gaps**.

The 9 not-applicable rows — refresh-token lineage and replay detection, PAT/OAuth
grant cascade, WebSocket/SSE cascade, geo/ASN and device-fingerprint filtering,
impossible travel, new-device detection — are listed so they stop re-appearing as
gaps. Four are posture decisions (§6), not missing work.

**Superseded by #3989 (2026-08).** otto 2.8 added country-level geo resolution
(`GeoResolver`), so the *country* half of 1.4, 6.1, and 6.2 is no longer N/A —
it moved to P2, buildable without reversing the masking posture (see
`geo-precision-profile-evaluation.md`). The ASN half of 1.4 and the
device-fingerprint half of 1.5/6.2 remain N/A, unchanged. The counts above (9
not-applicable, and the P0/P1/P2 tag distribution below) predate this split and
are not re-tallied here; treat "9 not applicable" as 9-minus-the-country-half
of three rows.

Read the 67 with two caveats. §7 is not seven independent gaps: every row there
is a _consequence_ of 3.1/3.2, so fixing one enforcement point closes the
section. And 9.1 is 1.6 restated from the anti-requirement side. The tag
distribution (4 P0 / 31 P1 / 32 P2) is also not a work plan — a P1 count in the
thirties carries about as much signal as no tags at all.

**The six rows that gate the others**, which is a dependency claim rather than a
ranking:

| Row                                                     | Gates                                                                                                                         |
| ------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| 1.6 — session ID in the console is the cookie value     | All of §4. Impersonation controls constrain nobody while the same operator can copy a live credential out of a read-only view |
| 3.1 + 3.2 — idle and absolute lifetime on the blob path | All of §7, and 1.8's `expires_at`                                                                                             |
| 5.3 — an external audit sink                            | 5.2, 5.4, 5.5, 5.6, 5.11. Tamper-evidence and retention are both cheaper downstream of a sink than in Redis                   |
| 2.5 — remember-me cascade                               | Any future work on the remember feature; wiring `load_memory` without it ships a revocation bypass                            |
| 8.1 — trusted proxy default                             | Every IP-bearing field in §1 and §5. Until it is on, those fields record the ingress hop                                      |

Twenty-two of the 67 were already itemized in `spec-session-path.md` §4/§5 and
are tagged KNOWN; the other 45 are new here. Anti-requirements: one violated
(9.1 = 1.6), one clean (9.2), one honoured by accident rather than by design
(9.3 = 2.14).
