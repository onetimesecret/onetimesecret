# docs/specs/macos-companion/06-open-questions.md
---

# Open Questions

Unresolved by design at milestone 1. Each has a current leaning where one
exists, so disagreement has a target.

## Product

1. **Default TTL.** Proposed 8h (a working day; short enough to be honest
   about the cache framing, long enough for the relay/multi-paste
   moments). Alternatives: 1h (purist) or 24h (forgiving). The default is
   the app's single most-felt setting.
2. **Does the TTL ladder wrap?** `…→ 7d → 1h` wrap is one-affordance-clean
   but makes "one click past max" a 168→1 hour cliff on deliberately
   staged content. Alternatives: stop at 7d with shift-click to shorten,
   or ←/→ semantics with click = reset only. Needs a prototype in hand.
3. **Cell cap.** Soft cap ~12 proposed, refuse-don't-evict at the limit
   (doc 04). Is refusal at the cap the right call under a fast triage
   workload, or does it interrupt exactly when the user is busiest?
4. **Persistence across restart.** v1 leaning: none — quit is amnesia,
   which is the cleanest trust story and the cache-true behaviour. But the
   "overnight hold" moment (doc 01) collides with an OS update reboot. If
   ever added: encrypted spill keyed via Keychain/Secure Enclave, off by
   default, and it must not soften the expiry contract.
5. **Expired-cell undo.** Discard has inline undo (misclick insurance).
   Does *expiry* deserve a seconds-long tombstone, or is silent removal
   (doc 03 §1) the promise? Leaning: silent; the user set the clock.
6. **Image support depth.** Thumbnails + copy-out in v1, but images fight
   the memory-hygiene story (size, mlock exclusion) and the v3 conceal
   payload is text-shaped. Ship text-first with images close behind, or
   together?
7. **Secret-shape detection.** Masking on `ConcealedType` is free; regex
   heuristics for keys/tokens risk false confidence both ways. How much
   detection is honest?
8. **Name.** "Airlock" collides with Airlock Digital. Shortlist and
   trademark pass needed before any public artifact.

## Platform & technical

9. **Shell decision.** Tauri 2.x vs Swift-shell-Rust-core (doc 05).
   Requires the two-way spike on the non-activating edge-docked panel —
   the one surface that can disqualify a framework.
10. **Sandbox + capture exclusion.** Verify App Sandbox coexists with
    `sharingType = .none` and the pasteboard patterns we need; sandboxing
    is worth real effort but not worth losing capture exclusion.
11. **Distribution.** Direct download + Homebrew cask (leaning), or also
    Mac App Store (sandbox implications, review friction vs reach)?
12. **Guest-mode prominence.** Where servers allow guest conceal, does the
    panel offer promotion with zero configuration out of the box (great
    for self-hosters, but link provenance/trust questions for
    onetimesecret.com defaults)?
13. **TTL semantics across promotion.** Snap cell-remaining time to
    server-allowed TTLs — up, down, or nearest? Down is the conservative
    (never outlive intent) leaning.
14. **Multi-display / multiple edges.** One panel on one edge of one
    display in v1; is that acceptable for the docked-monitor crowd?

## Ecosystem

15. **Windows/Linux siblings.** The core-crate split keeps the door open;
    naming it "macOS companion" closes it rhetorically. Decide posture
    before announcing.
16. **Relationship to future v3 PASETO work.** The desktop app is a
    real first consumer of v3 auth — should its needs (long-lived org
    tokens, device-ish identity, offline grace) feed back into that
    design now, while it's unbuilt?
