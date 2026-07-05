---
id: "019"
status: accepted
title: "ADR-019: At-Most-Once Secret Reveal"
---

## Status

Accepted

## Date

2026-07-05

## Context

Our core product requirement is that secrets can only be viewed a single time. This rule applies to all paths where plaintext is exposed: when a recipient opens a shared link, and when a creator views a generated value on the receipt page.

To enforce this "one-time-only" behavior, we have to work around two main constraints:

1. **At-Most-Once Delivery:** Because network requests can fail after a server has already marked a secret as read, we cannot guarantee "exactly-once" delivery. If we tried to guarantee "at-least-once" delivery, we would risk allowing a secret to be read twice—which violates our security model. Therefore, we must design for "at-most-once" delivery. If a request fails mid-transit, the secret is lost.
2. **GET Request Safety (#3633):** The creator's receipt page is served via a `GET` request. To keep `GET` requests safe and idempotent, loading this page should not directly mutate the secret's main lifecycle `state`.

## Decision

**Every plaintext exposure is guarded by an atomic, single-winner claim in
Valkey; on any ambiguity the value is withheld — the guarantee fails closed (at
most once), never open (at least once).** Concurrency, retries, and replays
cannot produce a second reveal: exactly one caller wins the claim, and every
other caller is denied with the ciphertext withheld.

| Surface | Claim | Losers get |
|---|---|---|
| Recipient reveal | `Secret#win_reveal_claim!` — CAS `state: new/previewed → revealed`, then the record is destroyed | `ciphertext = nil`, terminal state |
| Creator preview | `Receipt#claim_secret_value_display!` — atomic claim on the one-way `secret_value_shown_at` | `false`, no plaintext |

Both decide **inside Valkey**, so there is no read-modify-write window for two
requests to both pass. Both claim **before** returning the value: a lost
response forfeits the reveal rather than risking a second.

**Consumption gate, not lifecycle state.** The creator-preview claim is a
dedicated one-way timestamp that gates *only* the one-shot display, so the
receipt `GET` stays state-neutral per #3633. The recipient reveal is a genuine
lifecycle transition and legitimately advances `state`.

## Trade-offs

- **We lose**: exactly-once delivery — a reveal whose response is lost is
  forfeited (shown zero times) and must be re-shared.
- **We gain**: a hard impossibility of double-reveal under concurrency, retry,
  or replay.
- **Risk**: any new plaintext-exposing path must route through one of these
  claims; a bare decrypt-and-return silently reintroduces multi-reveal. New
  reveal surfaces are the thing to guard in review.

## Implementation Notes

### Open follow-ups (2026-07-05)

- **Familia claim primitive.** The creator-preview claim is a hand-rolled Lua
  check-and-set because Familia (v2.11.x) persists declared fields as the
  serialized nil `"null"`, so `HSETNX` never fires. Replace with the native
  primitive expected in Familia v2.11.2; the model specs pin the semantics.
- **v1 concealed-value divergence.** The once-only bound holds on all paths, but
  legacy v1 also reveals *concealed* (user-supplied) values to the creator,
  where v2/v3 reveal only *generated* ones. Aligning v1 down is a separate
  behavior change; it does not affect the bound.
