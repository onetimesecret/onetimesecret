# docs/specs/colonel-ui/spec-session-path.md

## created: 2026-07-27

Companion to `spec-session-performance.md` (why the console is slow) and
`spec-session-expectations.md` (what a super-admin session feature should do).
This one answers: **is there a path?** Yes for both, and they are cheaper than
either spec assumes — because half the machinery is already built and neither
spec credits it.

One correction and one conflict govern everything below:

- The performance spec says "nothing maintains an index." That is **wrong**, and
  it is the load-bearing claim. See §1.
- The two specs **contradict each other** on IP/device data. The expectations
  doc wants IP/geo/ASN filtering and impossible-travel detection; the performance
  doc's "What not to track" forbids exactly that, and Otto already masks IP
  upstream. This is not reconcilable by implementation — it is a posture decision
  the operator has to make explicitly. See §5. (**Update 2026-08, #3989:** the
  *country* half of "geo" has since dropped out of this conflict — it never
  needed the unmasked address. ASN, device fingerprinting and impossible travel
  are unaffected and the conflict stands for them. See §5.)

---

## 1. The index already exists — per customer

`spec-session-performance.md:34` argues no list/set/zset gives an accurate count
"because nothing maintains an index," and proposes building one with a ZADD per
session write. That index is already there:

| Piece | Location | State |
| --- | --- | --- |
| ZSET of live sids, scored by last activity | `Customer#active_sessions` — `sorted_set :active_sessions` (`lib/onetime/models/customer.rb:125`) | Built |
| The ZADD, on every authenticated write | `TrackMetadata#call` (`lib/onetime/operations/sessions/track_metadata.rb:83`) | Built |
| Lightweight per-session record (no decrypt) | `Onetime::SessionMetadata` — `created_at`, `last_activity_at`, `ip_address`, `user_agent`, `auth_method`, `org_id`, `user_id` | Built |
| No-scan / no-decrypt read + self-healing prune | `ListForCustomer` (`lib/onetime/operations/sessions/list_for_customer.rb`) | Built |

So the per-write cost the performance spec budgets for is **already paid** on
every authenticated request, and `ListForCustomer` is already a working
demonstration of the exact read pattern the spec proposes — ZSET range, resolve
sidecars, reconcile against blob liveness with an `EXISTS`-only probe.

The performance spec also reaches the right conclusion at its own line 46 —
split anonymous from identity at write time, since the console "only ever
displays identity sessions anyway." That split is half-built too: `TrackMetadata`
gates on `session_data['authenticated']`, so the index is identity-only by
construction.

**What is missing is only the global scope.** `Sessions::List` still scans and
decrypts the whole keyspace because there is no *global* equivalent of
`active_sessions`. That is one ZADD beside the one already at
`track_metadata.rb:83`.

Everything else in the performance spec's diagnosis holds and is confirmed:
sequential un-pipelined `GET`s (`list_sessions.rb:100`), per-value AES-256-GCM
decrypt, in-memory sort-then-paginate, and `Store.count` reporting exactly 10,000
forever because it is `scan_keys(...).size` against `MAX_SCAN` (`store.rb:170,
43`), re-run a second time for the Overview tile (`get_colonel_stats.rb:49`).

### 1a. Three things that will break a naive global index

Do not treat this as a copy-paste of `ListForCustomer`. Three differences bite:

**Email and role are not in the sidecar, deliberately.** `Store.summarize`
returns `email` and `role`; `SessionMetadata.safe_dump_fields` returns neither,
and the model docstring names that omission as the feature's security boundary
("Adding a field here is a deliberate act of exposing it"). The admin UI *does*
render both — `AdminSessions.vue:67-68` has `email` and `role` columns, plus
`email` in the detail panel and modal subtitle. So: hydrate email/role per
**displayed row** via `Customer.find_by_extid(meta.user_id)` — 50 bounded loads
per page, no decrypt. Do **not** add email to the sidecar; that reverses a
documented decision for a presentation convenience.

**Global free-text search cannot be served from the index.**
`Store.matches_search?` filters on email/extid, which the index does not carry.
This is the one capability a paginated index genuinely cannot provide. Route it:
resolve the search term to a customer, then serve from `ListForCustomer`. The
per-customer path already exists and is already exact.

**Pruning needs a threshold, not an expiry score.** With last-activity scoring,
prune is `ZREMRANGEBYSCORE index 0 (now - max_lifetime)` — pick the threshold
conservatively from the maximum session lifetime, and then whether `expire_after`
is uniform across session types stops mattering. For exactness on what is
actually displayed, `EXISTS`-probe only the ~50 sids on the page, reusing
`Store.find_key`. Do not probe the whole index per request.

**Cutover:** a new global index starts empty. `write_session` fires roughly per
request, so active sessions self-populate within one request each — but idle-yet-
live sessions will not appear until they are next touched. Dual-read during
transition (use the index; fall back to the scan when it is empty), or accept and
document the lag. Skipping this is the single most likely way to make it look
like every session vanished.

---

## 2. Counts

`ZCARD` on the global identity index is exact and O(1) — it replaces the
permanent, misleading 10,000 in both the list response and the Overview tile.

Anonymous is then derived, per the performance spec's correct reasoning at its
§"Don't keep a separate count": anonymous sessions have no logout path, so a
write-time counter over-counts continuously and a chokepoint counter is
meaningless. `anonymous = total − identity`, with total from a background,
**uncapped**, count-only cursor scan.

The performance spec's warning here is the important one and it is right: that
job must not call `Store.scan_keys` or `Store.count`, because both terminate in
`.first(MAX_SCAN)` — you would be building a corrector that fails in precisely
the regime that needs correcting.

**Prerequisite measurement, not an assumption.** `Store.key_patterns`
(`store.rb:53`) includes a bare `<sid>` shape with no prefix. No `*session*`
match can find those keys, so `total` is undercounted by however many bare-sid
keys exist in production, and `anonymous = total − identity` inherits the error.
Measure before relying on the derivation:

```
# Do bare-sid or legacy rack:session: keys still exist in prod?
redis-cli --scan --pattern 'rack:session:*' | head
# And the leak check the perf spec calls for — any -1 TTL is a real leak:
redis-cli --scan --pattern 'session:*' | head -1000   # then TTL each
```

---

## 3. The change that dissolves the problem

Indexing makes a large anonymous keyspace cheap to ignore. It does not stop
minting it. The performance spec's closing point is the highest-leverage item
here: if the bulk of the keyspace is CSRF-token-only sessions minted on anonymous
GETs of stateless pages, the fix is to stop creating them, not to count them
better.

Sequence this as a **peer** of the index work, not a footnote — but as an
investigation, not a known win. The synchronizer-token pattern needs a
session-backed token by construction
(`Rack::Protection::AuthenticityToken#set_token`, see
`lib/onetime/middleware/csrf_response_header.rb:43`), so the real question is
narrower: which anonymous GETs need a token issued eagerly, and can the rest mint
lazily on first state-changing use? If the answer is "most can be lazy," the
keyspace problem largely goes away and the index becomes a nicety.

The performance spec's four anonymous-hygiene metrics (first-write timestamp,
creation rate, cause-of-first-write, promotion rate) are the instrumentation that
answers this, and all four stand as written — `TrackMetadata` gates on
`authenticated`, so the sidecar's `created_at` covers identity sessions only and
anonymous sessions genuinely have no age signal today. Item 3 (cause of first
write, bucketed on the sorted key-signature) is the one that directly decides the
lazy-minting question. TTL every bucketed counter, per that spec.

---

## 4. Expectations: the precondition is already satisfied

`spec-session-expectations.md` opens by saying one architectural precondition
determines whether the rest is possible — **revocation must be authoritative
server-side** — and that everything else is downstream of it.

That precondition is met. Sessions die by deleting the encrypted
`session:<sid>` blob, not by expiring a stateless token:

- `RevokeAllForCustomer` deletes every tracked blob directly (exact, uncapped),
  then sweeps untracked blobs, purges sidecars, and **also** deletes the account's
  Rodauth `account_active_session_keys` rows so Rodauth-mounted routes lock
  immediately.
- Event-driven revocation on credential change already exists (#3810): the
  password-change/reset hooks revoke in-transaction, and
  `SessionRevocationSweepWorker` re-runs the full keyspace sweep asynchronously
  with a credential watermark so sessions authenticated *after* the change are
  spared.
- Deactivation revokes — `set_user_suspension.rb` revokes the customer's sessions
  and records the `ColonelAuditEvent`. The expectations doc's anti-requirement
  ("don't ship a delete-user that leaves sessions live") is already honoured.
- A CLI path exists (`bin/ots session`, over the same `Operations::Sessions`
  primitives) — the expectations doc's "revoke when the web UI is unreachable."
- Cookie hardening is configured, not assumed: `secure: true`, `same_site` =
  `lax` (`boot.rb`, passed through `middleware_stack.rb`), and the app warns
  loudly when a secure cookie is dropped behind a TLS-terminating proxy
  (`session.rb:261-271`).

So the expectations half is **incremental work, not architectural work**. That is
the main finding here.

### Real gaps, with evidence

**Remember-me cascade is broken.** This is the most important gap and it is
exactly the failure mode the expectations doc names ("Partial revocation is the
most common real-world bug"). The `remember_me` Rodauth feature exists
(`apps/web/auth/config/features/remember_me.rb`) and defaults to enabled
(`auth_config.rb#remember_me_enabled?`, `default: true`), yet **no session revoke
operation references remember-me at all** — `rg remember lib/onetime/operations/
sessions/*.rb` returns nothing. Revoking a session, or all of a customer's
sessions, leaves the remember cookie and its key row live to mint a fresh
session. Fix this before anything in §1.

**No session policy configuration.** The only knob is `expire_after: 86400`
(`config.defaults.yaml:315`). Missing: idle timeout, absolute lifetime,
remember-me max duration, step-up/sudo re-auth window, max concurrent sessions
and overflow behaviour, and per-role overrides — notably the expectations doc's
"admin sessions strictly shorter than user sessions." The compliance mapping it
cites (NIST AAL2 30 min idle / 12 h absolute, PCI DSS 4.0 §8.6.x 15 min idle,
HIPAA automatic logoff) is unreachable without idle-timeout support specifically.

**Impersonation is not a first-class session type.** Three files mention it
(`colonel_audit_event.rb`, `detect_host.rb`, `authenticate_session.rb`). The
expectations doc's requirements — required reason, time-boxed, non-nestable,
separately revocable, cannot target other super admins, banner, dual attribution
— are essentially unimplemented.

**`mfa_used` is declared but always nil.** The sidecar field exists;
`TrackMetadata#mfa_used` returns `nil` unconditionally and says so, because
`awaiting_mfa` is deleted on successful auth. The expectations doc's "MFA
satisfied y/n and factor type" needs an auth-time stamp, mirroring how
`auth_method` is already stamped in `hooks/login.rb`. That is the cheap fix.

### Cheap wins the existing data already supports

- **Concurrent session count per identity** — `ZCARD` on `active_sessions`.
- **Revoke all for a tenant/org** — the sidecar already carries `org_id`; no
  operation exposes it yet.
- **Global break-glass revoke** — the primitives exist; nothing composes them.
- **One-click quarantine** (disable account + revoke everything) — suspension
  already revokes; this is a UI composition.
- **Filter by auth method** — `auth_method` is populated and unused in the list.

---

## 5. The conflict you have to resolve, not implement around

The expectations doc asks for filtering by IP, geo/ASN and device fingerprint,
plus impossible-travel and new-device/geo detection. The performance doc's "What
not to track" rules out per-session IP, user agent and referer as "a visitor log,
on a privacy product — a larger liability than the problem it solves."

The codebase has already taken the performance doc's side. Otto masks IP upstream
before it reaches `session_data` (verdict-only matching, /24–/48 precision
profiles), and `TrackMetadata` copies `ip_address`/`user_agent` **as-is**
precisely because masking happened earlier.

**Update 2026-08 (#3989) — one item has left the third bullet.** I originally
lumped *geo* in with ASN and device fingerprinting on a single shared rationale:
you cannot locate a masked prefix. That rationale was right about the prefix and
wrong about country. otto 2.8's `Otto::Privacy::GeoResolver` never touches the
stored prefix at all — it resolves an ISO 3166-1 alpha-2 code (or the sentinel
`'**'`) from a trusted CDN header, or from an MMDB lookup on the already-masked
address, *before and independently of* what the sidecar ends up storing, and
publishes it as `env['otto.privacy.geo_country']`. Country is therefore not
reverse-derived from the /24–/48 prefix and adopting it loosens nothing. I have
split the bullet rather than rewritten it: everything below the country line is
unchanged, and **this section still governs the ASN half** — see
`geo-precision-profile-evaluation.md` and `spec-session-gap-analysis.md` row 1.4,
both of which cite it for exactly that. So:

- **Adoptable as written:** filter by user, tenant, auth method, created-at,
  last-seen. All backed by existing sidecar fields.
- **Degraded but useful:** "filterable by IP" means filterable by masked prefix
  (/24–/48), not by address. Fine for correlating a burst; useless for
  identifying a host. State this in the UI rather than implying precision the
  data does not have.
- **Adoptable without touching the posture (#3989):** country-level geo, and
  country only. Consumers read `env['otto.privacy.geo_country']` — they do not
  geo-locate anything themselves, and there is no code path from the stored
  prefix back to a location. `SessionMetadata#geo_country` already carries it.
  The precision-profile question this raises ("does accurate country need a
  looser mask?") was evaluated separately and answered *no*: see
  `geo-precision-profile-evaluation.md`. Note what did **not** move — otto
  resolves country and nothing else.
- **Not adoptable without reversing the privacy posture:** ASN lookup, device
  fingerprinting, impossible travel, new-device detection. ASN is not merely
  unbuilt but unavailable: otto has no ASN support at all, so there is no posture
  to reverse for it and nothing to adopt. Impossible travel does not come back
  with country either — but for the right reason now: country granularity is far
  too coarse to carry it. A country code cannot distinguish plausible movement
  from implausible movement inside a country, and across borders it is dominated
  by VPN egress and roaming. Building it inaccurately is still worse than
  omitting it. (What *is* newly conceivable at country granularity is the much
  weaker "new country for this account" signal — a different, noisier feature,
  and one to evaluate on its own merits, not an impossible-travel detector. See
  `spec-session-gap-analysis.md` rows 6.1 and 6.2.)

What is left after that split is still a decision for the operator, not a design
detail to implement around. Recommend keeping the current posture: the product is
a privacy product, the masking is deliberate and documented, and the detection
features are the least load-bearing part of the expectations list. If the posture
is ever reversed, it should be an explicit, configurable, self-hosted-operator
choice — not a default.

One expectations item that survives regardless and is worth confirming: **trusted
proxy configuration**. The doc is right that unparsed `X-Forwarded-For` makes
every session row read `127.0.0.1` and zeroes the compliance value. Scheme-level
proxy awareness exists (`ASSUME_HTTPS` / `X-Forwarded-Proto`, with the dropped-
cookie warning); confirm the IP-side trusted-hop list is configured in Otto
before claiming any of the IP fields mean anything at all.

---

## 6. Suggested order

1. **Remember-me revocation cascade.** A correctness bug in the security
   feature, independent of everything else, small.
2. **Global identity index** — one ZADD beside `track_metadata.rb:83`, plus the
   read path with email/role hydration, threshold prune, page-scoped `EXISTS`
   probe, and dual-read cutover. Fixes the console and the count together.
3. **Exact counts** — `ZCARD` for identity; background uncapped count-only scan
   for total; anonymous derived. Gated on the bare-sid keyspace measurement (§2).
4. **Anonymous minting investigation** — instrument cause-of-first-write, then
   decide whether CSRF tokens can mint lazily. Highest leverage; least certain.
5. **Session policy config** — idle timeout first (it is the compliance
   blocker), then absolute lifetime, remember-me max, max concurrent.
6. **Impersonation as a first-class session type** — largest, most self-contained,
   and unblocked by all of the above.

Items 1–3 are well-understood and safe. Item 4 may make item 2 partly redundant,
which is an argument for instrumenting early, not for delaying the index.

**Note:** none of this should be started on `feature/colonel-domain-configs` —
that branch is carrying unrelated uncommitted domain-config work.
