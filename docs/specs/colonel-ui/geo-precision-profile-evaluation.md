# docs/specs/colonel-ui/geo-precision-profile-evaluation.md

## created: 2026-08-08

The precision-profile evaluation deliverable for #3989 (geo-country adoption).
Acceptance criterion: **adopt or keep-current, with rationale.** Two questions,
not one — they get answered separately because they have different answers:

1. Should onetimesecret replace its single hardcoded IP-masking posture (IPv4
   /24 last-octet, IPv6 /48) with otto's per-surface named precision profiles
   (`:anonymous` / `:masked` / `:audit`), now that otto 2.8 exposes them?
2. Does adopting country-level geo resolution (also new in otto 2.8) change
   that answer — does accurate country data require more precision than the
   current masking posture keeps?

**Verdict: keep-current on both.** Do not adopt per-surface precision
profiles for storage, and do not loosen the masking posture for geo. The
detail and the rationale follow.

Related docs:

- `spec-session-gap-analysis.md` — rows 1.4 (filter by geo/ASN), 6.1
  (impossible travel), 6.2 (new device/geo). This doc is the evaluation those
  rows point to.
- `initial-build-out/40-sessions-metadata-sidecar.md` — the sidecar that now
  persists `geo_country` (#3989).
- ADR-021 (`../../architecture/decision-records/adr-021-audit-log-terminology-and-stream-scoping.md`)
  and ADR-022 (`../../architecture/decision-records/adr-022-secret-activity-network-capture-privacy.md`)
  — see §5.

---

## 1. What #3989 changed, precisely

otto 2.8 ships `Otto::Privacy::GeoResolver`, wired into the middleware stack
and **enabled by default** (`Otto::Privacy::Config#geo_enabled` defaults
`true`). It resolves an ISO 3166-1 alpha-2 country code — or the sentinel
`'**'` when nothing resolves — from, in order: an app-configured trusted
header, a known CDN/infra provider header (Cloudflare `CF-IPCountry`, AWS
CloudFront, Fastly, Akamai, Azure Front Door, Vercel, and a few semi-standard
names), a custom resolver hook, or a local MMDB country database. It never
guesses from a hardcoded range table — no hit means `'**'`, not a nearest
guess.

onetimesecret wires the result — `env['otto.privacy.geo_country']` — into
three places: `SessionMetadata#geo_country` (the sessions sidecar,
`40-sessions-metadata-sidecar.md`), the login/MFA alert emails, and,
gated, the Secret Activity trail (§5 below).

**Only country moved.** otto's `GeoResolver` has no ASN support — there is no
ASN half to this feature, and none of the geo/ASN won't-build rationale in
`spec-session-gap-analysis.md` changes for ASN. Read every "geo" reference in
this doc as "country," never as "geo including ASN."

---

## 2. The question this doc exists to answer

otto 2.8 also formalizes named privacy profiles on `Otto::Privacy::Config`:

| Profile      | Posture                                                          |
| ------------ | ----------------------------------------------------------------- |
| `:anonymous` | Mask every IP, including private/localhost                       |
| `:masked`    | Default — public IPs masked, private/localhost exempt             |
| `:audit`     | Privacy disabled — real IPs flow to env and logs; operator owns retention |

onetimesecret applies exactly one posture, globally, via the universal
`IPPrivacyMiddleware` mount (`middleware_stack.rb:296`, per
`spec-session-gap-analysis.md` row 1.3): IPv4 masked to /24 (last octet
zeroed), IPv6 to /48. No surface gets a different profile today. Now that
otto exposes named per-instance profiles, and now that a new capability
(country geo) has landed on top of the masked IP, it is worth asking whether
that single posture is still the right call — for storage in general, and for
geo specifically.

---

## 3. Key finding — country resolution is orthogonal to masking precision

Country accuracy does **not** depend on how coarsely the IP is masked before
storage. Two independent reasons, matching the two resolution paths:

**(a) Header-based geo is resolved before, and independent of, masking.**
When the request arrives via a trusted CDN, `GeoResolver` reads the
provider's country header (e.g. `CF-IPCountry`) directly — the CDN already
did its own geolocation upstream of onetimesecret entirely. This path never
touches the client IP at all, masked or not, so onetimesecret's
`octet_precision` setting is irrelevant to it.

**(b) MMDB country lookups operate at country-network granularity, which is
almost always coarser than /24.** When resolution falls through to the local
database, the lookup runs on the already-masked IP — otto's own
documentation states the guarantee directly: "Country-level MMDB networks are
almost always ≥ /24, so the default /24-masked value (`octet_precision: 1`)
resolves to the same country" (`otto/docs/geo-country.md`). Zeroing the last
IPv4 octet collapses 256 addresses into one masked value, but country-network
boundaries in the MMDB data essentially never fall inside a /24 — they are
allocated at /24 or coarser almost universally. So the masked address and the
real address resolve to the same country in practice.

(otto also documents the one setting that *could* create daylight here:
`octet_precision: 2`, a /16 mask, is coarser than some country ranges and can
push a small share of lookups to `'**'`. onetimesecret does not use
`octet_precision: 2` and has no reason to — see §4.)

**Conclusion: adopting country geo required zero change to the masking
posture, and no future masking change is required to keep it accurate.**
The privacy-vs-utility tradeoff that `spec-session-path.md` §5 worried about
for "geo/ASN" does not exist for the country half — masking was never in
tension with it. That is also why `spec-session-gap-analysis.md` rows 1.4,
6.1, and 6.2 could move off `N/A` without touching `IPPrivacyMiddleware` or
`config.defaults.yaml` at all.

---

## 4. Recommendation

**Keep the current single masked posture (/24 IPv4 last-octet, /48 IPv6) for
everything that gets stored.** No requirement surfaced by #3989 — or by the
gap analysis, or by the session-path spec — demands per-surface precision
profiles for stored data. Adopting `:anonymous`/`:masked`/`:audit` as
distinct **storage** postures per surface would be a real posture change (it
changes what persists in logs, sidecars, and audit trails) with no offsetting
benefit identified here: §3 shows geo doesn't need it, and nothing else in
this evaluation asked for it. Introducing it now would be solving a problem
#3989 doesn't have.

**For any future need for full-precision IP matching, use `otto.ip_match`
instead of raising stored precision.** otto 2.8 also exposes
`env['otto.ip_match']` — a verdict-only callable (`ip_match.call(cidrs) =>
true/false`) built from the *unmasked* client IP, available in **every**
privacy profile including `:masked` (per otto's own design note: "Precise
ephemeral matching against the unmasked IP does not require `:audit`").
It answers "is this request's IP inside these CIDRs" without ever persisting,
logging, or exposing the unmasked address — the precision lives only for the
duration of the check, not in storage. Any onetimesecret policy that turns
out to need real precision (trusted-network allowlisting, CIDR-scoped rate
limits, etc.) should reach for `otto.ip_match`, not for a weaker masking
profile.

**That adoption is tracked separately, not in #3989.** Wiring
`env['otto.ip_match']` into onetimesecret policy surfaces is issue **#4056**.
This doc records the recommendation and the reasoning; it does not implement
`otto.ip_match` adoption, and #3989's scope (country geo) does not require
it to land first or alongside.

Summary table:

| Question | Verdict | Why |
| --- | --- | --- |
| Adopt per-surface `:anonymous`/`:masked`/`:audit` storage profiles? | **No — keep current single posture** | Nothing in #3989 needs it; would be a posture change with no identified benefit |
| Does country geo require loosening masking? | **No** | §3 — header path bypasses masking entirely; MMDB path is coarser than /24 already |
| Where does precision-sensitive *policy* (not storage) go? | `otto.ip_match`, verdict-only, unmasked-but-unstored | Precision without persistence; tracked as #4056, out of scope here |

---

## 5. Org-tier Secret Activity country column — gated, not shipped by default

`SecretActivity`/`AuditTrail` gains a `geo_country` field alongside
`SessionMetadata`, but the **org-tier column that would surface it to org
admins is behind a default-OFF flag**, pending counsel review. This is
deliberate, not an oversight, and it follows directly from work already in
flight on the two adjacent audit-log ADRs:

- **ADR-021** (`adr-021-audit-log-terminology-and-stream-scoping.md`),
  Decision 4, already flags this exact class of data as an open question for
  Security Events: *"Fine-grained location/device data, jurisdiction-dependent
  ... Exposing every member's raw IP/location org-wide can cross into
  regulated employee-monitoring (GDPR proportionality; works-council rules in
  DE/FR) ... Confirm with counsel before exposing raw IP/UA org-wide."*
  Country is coarser than the raw IP/city-level data that language is aimed
  at, but it is still location data about an individual, surfaced to their
  org admin — the same proportionality question, at lower resolution. Decision
  4 has not been resolved for Security Events; it has not been asked at all
  for Secret Activity.
- **ADR-022** (`adr-022-secret-activity-network-capture-privacy.md`) covers
  exactly the Secret Activity network-context fields this doc's flag would
  extend — `net_ip_partial`, `net_ua_partial`, `net_ip_hash` — but **does not
  mention country or geo anywhere.** It was written before geo resolution
  existed in otto. Adding a country column to the org-tier trail is an
  extension of ADR-022's scope, not something it already decided.

Until an ADR-022 addendum (or a new ADR) explicitly clears org-tier country
exposure — ideally resolving ADR-021 Decision 4's open counsel-review question
at the same time, since it's the same underlying tradeoff — the org-tier
Secret Activity country column stays default-off. `geo_country` capture
itself (the underlying field, gated separately from its org-tier display) is
unaffected by this and follows the same masked-IP-input, honest-unknown
behavior described in §1.

---

## 6. Cross-references

- `spec-session-gap-analysis.md` §1 row 1.4 (filter by geo/ASN), §6 rows 6.1
  (impossible travel) and 6.2 (new device/geo) — the rows this evaluation
  backs.
- `initial-build-out/40-sessions-metadata-sidecar.md` — `geo_country` on
  `SessionMetadata`, populated via `TrackMetadata` from
  `env['otto.privacy.geo_country']`.
- `spec-session-path.md` §5 — the original masked-IP posture decision this
  doc confirms still holds for geo.
- `adr-021-audit-log-terminology-and-stream-scoping.md` Decision 4 — the open
  counsel-review question this doc's §5 flag is gated on.
- `adr-022-secret-activity-network-capture-privacy.md` — the Secret Activity
  network-context capture design this doc's §5 extends but does not amend.
- **#4056** — tracked separately: wiring `otto.ip_match` into onetimesecret
  policy surfaces. Not implemented by #3989 or by this doc.
