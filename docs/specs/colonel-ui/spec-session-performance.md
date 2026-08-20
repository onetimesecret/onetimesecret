# docs/specs/colonel-ui/spec-session-performance.md

## created: 2026-07-27

# Session Admin Performance

Three separate problems.

## Why it's slow

Onetime::Operations::Sessions::List#call (lib/onetime/operations/sessions/list_sessions.rb:59) does the whole thing on the request path, per request:

1. Store.scan*keys — SCAN MATCH \_session* TYPE string via scan_each with default COUNT (10). Matching is server-side, so with sessions a minority of the keyspace this is hundreds-to-thousands of round trips before it fills its window (store.rb:170).
2. One sequential GET per key — collect loops Store.load_data (list_sessions.rb:100). Not pipelined. Up to 10,000 serial RTTs.
3. AES-256-GCM decrypt + HMAC verify per value in Ruby (Store.load_data with codec).
4. Partition, filter, sort, then paginate in memory (list_sessions.rb:70-78).

Nothing is cached. Page 2 costs the same as page 1. Search re-scans. And the Overview stat tile runs the identical scan a second time through Store.count (get_colonel_stats.rb:49).

### Why the count is always 10,000

MAX_SCAN = 10_000 (store.rb:43). Store.count is literally scan_keys(dbclient).size, and scan_keys ends in .first(MAX_SCAN). It is not a count — it's "we stopped at the cap." Any keyspace above 10k session keys reports exactly 10,000 forever. The list response's scan_capped flag (list_sessions.rb:88) is the same truncation signal, which is why the UI shows the capped badge.

### Are they expiring?

Yes, at the code level. write_session does stringkey.set then update_expiration(expiration: @expire_after) (session.rb:~688), and get_stringkey sets default_expiration: @expire_after (session.rb:146). expire_after: 86400 (etc/defaults/config.defaults.yaml:315). Every write refreshes the TTL.

So it's generation volume, not leakage. A blob is written for any visitor whose session mutates — the CSRF token alone does it (Rack::Protection::AuthenticityToken#set_token, see lib/onetime/middleware/csrf_response_header.rb:43), plus domain_context, plus flash. Every bot, every one-shot secret viewer gets a 24h key. The code says as much: "Anonymous sessions (CSRF-token-only visitors) dominate the keyspace" (list_sessions.rb:65). That's your willy-nilly.

Caveat: that's a code claim, not a prod measurement. To falsify, sample for keys with no TTL: redis-cli --scan --pattern 'session:\*' | head -1000 then check TTL — any -1 is a real leak.

### Why no list/set/zset gives an accurate count

Because nothing maintains an index. Sessions are bare session:<sid> string keys written by Rack middleware; there is no registry to count. And you can't naively SADD on write, because Redis TTL expiry is invisible to the app without keyspace notifications — the set would fill with dead members and overcount permanently.

The shape that works is a ZSET scored by expiry:

- ZADD session:index <expires_at> <sid> in write_session, right where the TTL is already set.
- ZREM in delete_session (that hook already exists, session.rb:151).
- Before any read: ZREMRANGEBYSCORE session:index 0 <now> to evict members whose keys have expired.
- Count = ZCARD. Exact, O(1).
- List page = ZREVRANGEBYSCORE ... LIMIT offset count → one pipelined MGET of just those 50 ids. No scan, no cap, and page N costs the same as page 1.

Cost is one ZADD per session write. Self-healing too: score-based pruning means a missed ZREM corrects itself at the expiry boundary rather than drifting.

Separately, splitting anonymous CSRF-only sessions off the identity sessions at write time (two index ZSETs) would make the console page cheap regardless — it only ever displays identity sessions anyway.

We could keep a separate count of anonymous sessions? What information should we be tracking for anonymous for operational hygiene?

Existing infra check done — no HLL, no general metrics facility, but there's a directly relevant precedent. Let me get a second read before committing to a recommendation.

## Don't keep a separate count — derive it

The advisor's right that anonymous sessions lack a logout path, so counting them at a chokepoint inflates the numbers—I should derive anonymous by subtracting identified sessions from the total instead. For the reconciliation, I need to verify the scan doesn't get reused and check whether legacy rack:session: keys are still present in production, though I can at least document the four possible key formats. The write_session call happens on every request since the TTL gets refreshed each time.

The secrets_active precedent (counter_fields.rb) doesn't transfer here. That pattern works because most secrets die through a chokepoint (reveal/burn/delete) and TTL expiry is the exception — which is why a daily reconcile is enough. Anonymous sessions have no logout, so delete_session essentially never fires for them. TTL is the only termination path. A write-time anon counter would over-count continuously, by roughly a full day of traffic between reconciles. It'd be wrong nearly all the time.

Instead:

- Identity ZSET (from before) → ZREMRANGEBYSCORE then ZCARD = exact live identity count.
- Total session keys → count-only cursor scan in a background job.
- Anonymous = total − identity.

No second index, no anon counter, no decrypt pass. One caveat that matters: that job must not call Store.scan_keys/Store.count — both end in .first(MAX_SCAN) (store.rb:170), so you'd build a corrector that's broken in exactly the regime where correction is needed. It needs an uncapped cursor with a large COUNT, counting keys only. Worth confirming against prod whether session:\* covers everything or whether the legacy rack:session: shapes in key_patterns (store.rb:53) still have live keys.

### What to actually track

1. First-write timestamp. The highest-value item, and it's currently missing entirely: Store.summarize maps created_at to data['authenticated_at'] (store.rb:202), which is nil for every anonymous session. There is no age signal on them at all today. Stamp \_created_at on first write (absent ⇒ first write). That gives you age distribution and oldest-anon — the first two hygiene questions anyone asks.

2. Creation rate, per hour, TTL'd. Note write_session fires per request, not per session — TTL refreshes on every write — so a naive INCR there counts writes and inflates the rate by requests-per-session. The \_created_at-absent check from (1) is the free discriminator that makes the count honest. A rate is what detects a bot flood; a level tells you nothing actionable.

3. Cause of first write. write_session already has session_data.keys in hand (it's in the trace log). Bucket on the sorted key-signature: csrf alone vs csrf+domain_context vs flash, etc. This is what converts "we have a lot of anonymous sessions" into "94% are CSRF-token-only" — i.e. it tells you which ones you can stop minting.

4. Promotion rate — anonymous → authenticated. The denominator for whether session creation correlates with real usage at all.

Put TTLs on every bucketed counter, or you've traded a bounded session keyspace for an unbounded metrics keyspace.

### What not to track

No per-session IP, user agent, or referer. That's a visitor log, on a privacy product — a larger liability than the problem it solves, and inconsistent with the verdict-only posture of the existing IP middleware. The four metrics above carry no visitor data at all, so the privacy-safe answer and the useful answer are the same one here.

### The point of all four

Every one of these exists to answer one question: can we stop creating these? If (3) says the bulk are CSRF-only sessions minted on anonymous GETs of a stateless page, the fix isn't better counting — it's deferring the session commit until something durable actually needs storing. That deletes the mass rather than measuring it.

---

A re-analysis:

The performance spec's load-bearing claim is wrong. It says "nothing maintains an index" and budgets for a ZADD per session write. That index exists: sorted_set :active_sessions (customer.rb:125), written on every authenticated write at track_metadata.rb:83, with ListForCustomer already demonstrating the exact no-scan/no-decrypt read pattern the spec proposes — including self-healing reconcile. The per-write cost is already paid. What's missing is only the global scope: one ZADD beside the existing one. The spec's own line 46 (split anonymous from identity at write time) is likewise half-built, since TrackMetadata gates on authenticated.

The rest of its diagnosis holds — sequential un-pipelined GETs, per-value decrypt, the permanent 10,000 from scan_keys(...).size against MAX_SCAN, run twice.

Three things break a naive copy of the per-customer pattern, all in the doc: email/role aren't in the sidecar by documented security decision but the UI renders both (AdminSessions.vue:67-68) — hydrate per displayed row, don't widen the allow-list; global email search can't come from the index at all — route it through customer resolution; and the index starts empty, so cutover needs dual-read or sessions appear to vanish.

The expectations spec's stated precondition is already satisfied. Revocation is authoritative server-side — blob deletion is the kill, RevokeAllForCustomer also clears Rodauth account_active_session_keys, #3810 wires event-driven revoke on credential change with an async sweep, suspension revokes, the CLI path exists, and same_site/secure are configured. So that half is incremental work, not architectural.

One real bug fell out. remember_me is enabled by default, and no session revoke operation references remember-me anywhere. Revoking sessions leaves the remember cookie live to mint a fresh one — precisely the "partial revocation" failure the expectations doc calls the most common real-world bug. I put it first in the sequence.

The two specs contradict each other and I did not merge them. Expectations wants IP/geo/ASN filtering and impossible travel; performance's "what not to track" forbids it, and Otto already masks IP upstream. Impossible travel isn't buildable accurately, because country granularity is far too coarse to carry it — a country code can't separate plausible from implausible movement, and across borders it's dominated by VPN egress and roaming. I classified each item as adoptable / degraded / needs-an-explicit-posture-reversal, and recommended keeping the current posture — that's the operator's call, not an implementation detail. (**Update 2026-08, #3989:** I first wrote that sentence as "isn't buildable accurately on masked prefixes." That reason is obsolete. otto 2.8 resolves country from a trusted CDN header or an MMDB lookup on the already-masked address and publishes `env['otto.privacy.geo_country']` — never by reverse-locating the stored /24–/48 prefix — so country-level geo is buildable and adopting it doesn't loosen the masking. Country is the only thing that moved: ASN has no otto support at all, device fingerprinting is still uncollected, and impossible travel stays out on the coarseness ground above. See `spec-session-path.md` §5 and `geo-precision-profile-evaluation.md`.)

Two things I flagged rather than assumed: key_patterns includes a bare <sid> shape no pattern can match, so anonymous = total − identity needs a prod measurement first; and the anonymous-minting question (item 4) is an investigation, not a known win — the synchronizer pattern needs session-backed tokens, so the real question is whether anonymous GETs can mint lazily.
