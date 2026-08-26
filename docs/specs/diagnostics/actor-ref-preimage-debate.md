# Debate Brief: The Actor Reference Pre-Image

**Date:** 2026-08-22
**Branch:** `feat/diagnostics-signal-quality` (PR #4250)
**Question:** What value should be fed into the keyed derivation that produces the
pseudonymous Sentry `user.id` (`DiagnosticsRef.actor_ref`)?
**Status:** Unresolved. PR #4250 ships the email pre-image; a rework to the
extid pre-image is on the table following the values clarification in Round 5.

---

## Candidates

| # | Pre-image | Origin |
|---|-----------|--------|
| A | Normalized account email (shipped) | `lib/onetime/utils/diagnostics_ref.rb` |
| B | Customer/organization extid | Proposed in Round 1, revived in Round 5 |
| C | Precalculated federation email hash (stored field) | Proposed in Rounds 2–3 |
| D | New stored `actor_identifier` field, federation-keyed, identical across fleet regions | Proposed in Round 4 |

All candidates assume the ref itself remains a keyed, truncated,
purpose-prefixed HMAC. The debate is about the input, not about sending
anything raw.

---

## Round 1 — Why email over extid (the original decision)

**Case for A (email):**

1. **Federated scope requires a cross-install identity.** Regional instances
   share `FEDERATION_SECRET`; the same human on two federated installs has two
   unrelated extids but one email. `HMAC(extid)` can never correlate across
   installs. This mirrors why `EmailHash` (federation) is email-keyed.
2. **Lifecycle stability.** Extid dies with its record; delete-and-recreate
   splits one human into two Sentry users. Email keeps "one account or fifty"
   answerable.
3. **Uniform availability.** Email is present at boundaries where no loaded
   customer record exists:
   - Rodauth account-lifecycle hooks where the Customer is being created
     (`create_customer`), linked (`claim_pending_federation`), or destroyed
     (`delete_customer`) — the extid is the thing failing to exist or being
     deleted.
   - Credential flows keyed on a submitted email (reset, magic link,
     verification) where the authdb lookup may itself be what raised.
   - Controller/middleware rescues during datastore outages: `safe_cust`
     documents that `#cust` lazily loads from Valkey and can raise, and capture
     runs exactly when things are failing. Session identity is email-shaped
     (`custid` is historically the email); extid needs the read that just
     failed.
   - Logic-layer `safe_execute` callers holding only an email string.
4. **The asymmetry is deliberate.** `organization_ref` keys on the org objid
   because an org is a per-install resource with no cross-instance identity and
   no reconciliation problem.

**Framing note that held throughout:** the choice of pre-image is about
correlation semantics, not disclosure. Nothing raw is sent under any candidate;
email, custid, and extid are equally forbidden as raw values at every capture
boundary.

**Outcome:** A adopted; B's coverage gaps treated as disqualifying.
(Re-litigated in Round 5 under different values.)

---

## Round 2 — Why not the precalculated federation hash (C)

**Proposal:** a stored field derived from email + `FEDERATION_SECRET` already
exists (for purposes of this debate); use it as the derivation input, and put
it in `/bootstrap/me` so the frontend always has it.

**As server-side pre-image — rejected:**

- **Buys nothing.** The full derivation layer (purpose prefix, residency
  element, scope fallback, truncation) is needed regardless of input; the email
  is already in hand at every boundary; hashing a hash gains no privacy
  (a keyed pseudonym of a pseudonym is still personal data, GDPR Recital 26).
- **Availability inverts.** A stored field lives on a record; boundaries that
  haven't loaded it would need a datastore read inside the error path — the
  exact hazard `DiagnosticsRef`'s failure-tolerance design engineers against.
- **Scope entanglement.** The deployment-scoped fallback (`ACCOUNT_ID_SECRET`,
  serving installs with no residency declared — the majority population) would
  depend on a federation-keyed artifact existing at write time.

**As a bootstrap field — refused outright:**

- The field is simultaneously a queryable Redis index and a Stripe customer
  metadata value: a live join key into the datastore and billing records.
  Bootstrap ships it to the browser — devtools, HAR captures, extensions, one
  breadcrumb away from the event payload — and the browser is precisely what
  feeds Sentry.
- It is region-independent by design (one value per person fleet-wide), which
  is the cross-jurisdiction join the residency derivation exists to prevent.
- It has no scope-narrowing fallback and couples diagnostics rotation to
  federation rotation (Stripe metadata rewrite, index rebuild). The `v1`
  purpose prefix exists so diagnostics can re-key independently.
- The stated goal ("frontend always has it") is already met: bootstrap carries
  `actor_ref`/`actor_scope`, which is the same email-plus-secret idea made
  purpose-bound, residency-scoped, independently rotatable, and shape-distinct.

---

## Round 3 — The staleness challenge

**Challenge:** "A stored value can be missing or stale — who cares? This isn't
a correlation identifier since the dawn of time; Sentry retains 14 days max."

**Conceded:** staleness-over-time is neutralized by retention. A row hashed
under an old secret stays self-consistent within any window; the
"stale since the dawn of time" argument was garnish.

**Survived:**

- **Missing is cohort-bounded, not time-bounded.** Rows written while the
  secret was unconfigured (the default state) have no stored value in *every*
  window until backfilled. The fallback is deriving from email — the thing
  being avoided — producing a two-path scheme.
- **Redundant or split; no third outcome.** Either the stored value is
  byte-identical to fresh derivation (a cache of a sub-microsecond HMAC) or it
  differs, and the same human gets different refs from the two paths *inside
  the same window*. A mid-window backfill flips accounts between refs.
- **The binding consistency constraint is cross-surface, not cross-time.** The
  ref must come out identical at the bootstrap serializer, controller rescues,
  Rodauth hooks, and middleware simultaneously; several of those boundaries
  cannot reach a stored field, so fresh derivation is mandatory regardless, and
  a stored copy is a second source of truth.

---

## Round 4 — The federated `actor_identifier` field (D)

**Proposal:** don't reuse the existing field; add a new federation-keyed
`actor_identifier` computing to the same value in every fleet region. "If it
works for carrying Stripe subscriptions across regions, it works for this."

**Rejected — this is the module's own v0, already ruled a defect:** an earlier
revision keyed refs off `FEDERATION_SECRET` alone and sold region-independence
as a feature; the residency element was added unconditionally, with no opt-out,
"because an opt-out would exist only to reconstruct the hazard." A
region-stable stored field is that opt-out as a schema addition.

**Why the Stripe precedent does not transfer — the disclosure-boundary
distinction:**

- **Stripe is a party allowed to know it's the same person.** Cross-region
  linkage is the *purpose* of the federation hash there: subscription carryover
  is the product feature, server-to-server, inside an already fully identified
  billing relationship. The hash discloses nothing Stripe doesn't hold.
- **Sentry is a party deliberately kept unable to know.** All regions report to
  one shared backend and every event carries a `jurisdiction` tag; a
  region-stable `user.id` makes "this data subject is present in both EU and
  US" a standing, searchable fact — the inference the jurisdictional-residency
  architecture exists to make impossible.

**Purpose test:** every widening must justify itself against diagnosing a
defect. Cross-region correlation has no defect-diagnosis use (EU traces are
debugged against EU code/config/datastore); "is this the same human erroring in
the US" is product analytics, which this data is not allowed to answer.

**The legitimate fleet case already works:** installs sharing
`FEDERATION_SECRET` within one residency scope derive identical refs today
(`federated` scope). D's only increment over the shipped design is
cross-jurisdiction correlation — exactly and only the prohibited part.

---

## Round 5 — The values reordering (the actual position)

**Position stated:** strong preference not to involve the email address at all,
even at the cost of poorer diagnostics. Bayesian framing: the value of privacy
(actual and perceived) is not the same order of magnitude as a technocrat's
ability to debug systems they built.

**Two genuine privacy costs of the email pre-image, previously underweighted,
conceded:**

1. **Emails are enumerable; extids are not.** `HMAC(secret, email)` is
   confirmable by anyone holding the secret plus a candidate list, and email
   lists are cheap: a leaked `FEDERATION_SECRET` plus a Sentry export enables
   offline dictionary re-identification. `HMAC(secret, extid)` is inert under
   the same leak — the pre-image is high-entropy and lives only in the
   datastore. The email pre-image concentrates tail risk on secret compromise;
   this is precisely the low-probability, high-severity term the Bayesian
   framing weights.
2. **Email-derived refs survive erasure.** Delete the account, re-sign-up with
   the same address inside the retention window, and new events re-link to
   pre-deletion ones. What Round 1 sold as lifecycle stability is, under this
   ordering, a privacy defect. An extid-derived ref dies with the record,
   permanently orphaning old events — which is what deletion should mean.

**Design that follows (B, revised):** extid pre-image, still HMAC'd and
truncated (extids appear in API responses and logs; an unkeyed hash is a
trivial join), keyed by `ACCOUNT_ID_SECRET` only.

- Drops `FEDERATION_SECRET` from diagnostics entirely.
- **Deletes the residency apparatus instead of enforcing it:** extids are
  minted per-region, so cross-region correlation becomes structurally
  impossible rather than discipline-dependent. The module shrinks, and the
  most important property stops depending on future editors maintaining a
  derivation invariant.

**Price, stated for eyes-open purchase:**

- Attribution disappears at email-only boundaries (auth surface,
  account-creation/deletion failures, credential flows, datastore-outage
  rescues). Those events are still captured and still grouped by the grouping
  rules; they carry no user, so "one account or fifty" goes unanswered for that
  class.
- A returning user after deletion counts as a new user.
- The loss is narrower than Round 1 implied: the bootstrap serializer,
  controller captures, and most Rodauth hooks have an extid in hand.

---

## Principles that emerged

1. **Purpose test.** This is diagnostics, not analytics. Every widening of
   disclosure must justify itself against diagnosing a defect; "it would be
   interesting to know" is a refusal.
2. **Disclosure-boundary parties.** Distinguish consumers allowed to know an
   identity fact (Stripe, for federation) from consumers deliberately kept
   unable to know it (Sentry). A mechanism that "works" for the first class is
   not a precedent for the second.
3. **Structural impossibility beats enforced invariants.** A hazard made
   unrepresentable (per-region pre-images) is stronger than a hazard prevented
   by derivation discipline (unconditional residency mixing), which is itself
   stronger than one prevented by configuration (the rejected opt-out).
4. **Consistency binds cross-surface, not cross-time.** Retention forgives
   temporal drift; nothing forgives the same human carrying two refs in one
   window across frontend and backend events. One derivation path, no second
   source of truth.
5. **Pre-image entropy is a privacy property.** Deterministic derivation from
   an enumerable identifier is dictionary-attackable under key compromise;
   derivation from a high-entropy server-minted token is not. "It's keyed" is
   not the end of the analysis.
6. **Erasure semantics are part of the design.** An identifier that re-links a
   data subject across an account deletion contradicts what deletion promises,
   independent of retention length.
7. **Values ordering is an input, not an output.** The email pre-image was the
   correct engineering answer to "maximize diagnostic correlation subject to no
   raw disclosure." It is not the answer to "minimize identity involvement,
   accepting poorer diagnostics." The second ordering was the operator's actual
   position, and it selects the extid design.

## Decision record

- PR #4250 currently ships candidate A (email pre-image).
- Candidates C and D are rejected with prejudice (Rounds 2–4).
- Candidate B (extid pre-image, `ACCOUNT_ID_SECRET`-keyed, residency apparatus
  removed) is the design implied by the Round 5 values ordering. Rework is a
  contained change to `DiagnosticsRef`, `ErrorHandler.diagnostics_actor`
  candidate handling, and specs; net code shrinks. Awaiting go/no-go.
