---
id: '019'
status: accepted
title: 'ADR-019: At-Most-Once Secret Reveal'
---

## Status

Accepted

## Date

2026-07-05

## Context

Our core product requirement is that a secret's plaintext can be viewed a single
time. This applies to every path that reveals plaintext: a recipient opening a
shared link, and a creator viewing a generated value on the receipt page.

This ADR exists because that guarantee was briefly lost and then restored, and
the repair is worth recording so it is not undone the same way. The #3633 work
that stopped the receipt-page `GET` from mutating secret state — necessary to
keep the `GET` idempotent — also stopped stamping the creator-side preview
transition, which had been the _de facto_ view-once gate: with nothing recording
that the creator had already seen the value, the generated value could be shown
again on a later load, and two concurrent first-loads could both show it. That
one state mutation had been quietly doing two unrelated jobs — receipt-page
bookkeeping and view-once enforcement. This ADR splits them: the `GET` stays
state-neutral, and view-once is enforced by a dedicated atomic claim instead.

Three forces shape the decision:

1. **Concurrency and replay, not just a single slow reader.** Two requests can
   load the same secret, both observe an in-memory state that still permits a
   reveal, and — with no atomic guard — both decrypt and return the plaintext. A
   read-check-then-write cannot close this window; the single winner must be
   decided indivisibly, inside Valkey.
2. **At-most-once, never at-least-once.** A network response can be lost after
   the server has already committed the reveal. We therefore claim _before_
   returning the value: a lost response forfeits the reveal (shown zero times)
   rather than risk a second. Designing toward at-least-once delivery would
   permit a double read, which violates the security model.
3. **GET-request safety (#3633).** The creator's receipt page is served via a
   `GET`. Keeping it idempotent means the page load must not advance the secret's
   lifecycle `state` — which is exactly why the view-once gate can no longer be a
   lifecycle mutation and must instead be a dedicated one-way claim.

## Decision

**Every plaintext reveal is guarded by an atomic, single-winner claim in
Valkey; on any ambiguity the value is withheld — the guarantee fails closed (at
most once), never open (at least once).** Concurrency, retries, and replays
cannot produce a second reveal: exactly one caller wins the claim, and every
other caller is denied with the ciphertext withheld.

| Surface          | Claim                                                                                            | Losers get                         |
| ---------------- | ------------------------------------------------------------------------------------------------ | ---------------------------------- |
| Recipient reveal | `Secret#win_reveal_claim!` — CAS `state: new/previewed → revealed`, then the record is destroyed | `ciphertext = nil`, terminal state |
| Creator preview  | `Receipt#claim_secret_value_display!` — atomic claim on the one-way `secret_value_shown_at`      | `false`, no plaintext              |

Both decide **inside Valkey**, so there is no read-modify-write window for two
requests to both pass. Both claim **before** returning the value: a lost
response forfeits the reveal rather than risking a second.

**Consumption gate, not lifecycle state.** The creator-preview claim is a
dedicated one-way timestamp that gates _only_ the one-shot display, so the
receipt `GET` stays state-neutral per #3633. The recipient reveal is a genuine
lifecycle transition and legitimately advances `state`.

## Trade-offs

- **We lose**: exactly-once delivery — a reveal whose response is lost is
  forfeited (shown zero times) and must be re-shared.
- **We gain**: a hard impossibility of double-reveal under concurrency, retry,
  or replay.
- **Risk**: any new plaintext-revealing path must route through one of these
  claims; a bare decrypt-and-return silently reintroduces multi-reveal. New
  reveal surfaces are the thing to guard in review.

## Implementation Notes

### Open follow-ups (2026-07-05)

- **Familia claim primitive.** The creator-preview claim is a hand-rolled Lua
  check-and-set because Familia (v2.11.x) persists declared fields as the
  serialized nil `"null"`, so `HSETNX` never fires. Replace with the native
  primitive expected in Familia v2.11.2; the model specs pin the semantics.
- **v1 concealed-value divergence.** The once-only bound holds on all paths, but
  legacy v1 also reveals _concealed_ (user-supplied) values to the creator,
  where v2/v3 reveal only _generated_ ones. Aligning v1 down is a separate
  behavior change; it does not affect the bound.

## References

The two claims named in the Decision table are the review anchors — any new
plaintext-revealing path must route through one of them:

- **Recipient reveal** — `Secret#win_reveal_claim!` / `#reveal!`
  (`lib/onetime/models/secret/features/secret_state_management.rb`). CAS on the
  lifecycle `state` field via `compare_and_set_state!`; `reveal!` decrypts only
  inside the won-claim branch so plaintext cannot be obtained without winning.
- **Creator preview** — `Receipt#claim_secret_value_display!`
  (`lib/onetime/models/receipt/features/access_timeline.rb`), built on the
  one-way `claim_once!` Lua CAS on `secret_value_shown_at`. The same file's
  `record_receipt_view!` is the state-neutral telemetry counterpart from #3633.
- **Issue #3633** — the receipt state/telemetry split whose GET-safety fix this
  ADR completes. Commits `f4de11ec3` (stop GET mutating state) and `eea1b86e6`
  (show a generated value exactly once).
- **ADR-008** — Secret Management Architecture, for the cryptographic key
  lifecycle these reveals operate within.
