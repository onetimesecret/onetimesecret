# UX analysis of the "no longer available" failure surface

Companion to `docs/specs/unviewable-state-root-cause.md`. That document
establishes the *mechanism* (an out-of-enum / un-viewable `state` triggers a 404
on the recipient path and a strict-schema parse failure on the sender path, both
rendered as the same terminal screen). This document revisits the *user
experience* of that whole failure surface — the conceptual and practical
challenges it creates for the sender and the recipient — and proposes a
prioritized set of remedies. It describes current `develop`.

## How this was produced

A multi-specialist panel analysed the live screens and code from six independent
lenses — a visual information theorist, a psychoanalyst, a UX researcher, an
elderly caretaker, a trust & safety / security-communications specialist, and a
support / operations lead. Their findings were synthesised into the framework
below, then pressure-tested by an adversarial reviewer (security + completeness)
whose corrections are folded in (see "Changes from review"). Load-bearing
structural claims were verified against the source:

- The terminal copy `web.secrets.that_information_is_no_longer_available` =
  "This secret has been viewed or expired." is shared by both
  `src/apps/secret/reveal/UnknownSecret.vue` (recipient) and
  `UnknownReceipt.vue` (owner).
- `StatusBadge.vue` imports `receiptStateSchema` from `schemas/shapes/v3/receipt`
  (which **excludes** legacy `viewed`/`received`, v3 receipt.ts:27-28) and calls
  `.parse()` — which **throws** on a legacy value before `getDisplayStatus`s v2
  alias map (`status.ts`, importing from `schemas/shapes/v2`) is ever reached.
- `receiptListStore.ts:90-101` runs a **single** `gracefulParse` over the whole
  response and, on failure, sets `records = []` / `details = {}` / `count = 0` —
  one poisoned row empties the entire dashboard.
- `UnknownReceipt.vue` hard-codes `:branded="false"` and has no
  `branded/UnknownReceipt.vue` sibling; its `aria-label` key
  (`information_no_longer_available`) differs from its visible h1 key.

This is an analysis and recommendation document; it proposes no code changes by
itself. Opportunity IDs (Q1–Q9, S1–S12, C1–C8) are referenceable in follow-up
issues.

---

# UX Strategy Report — Issue #3424: The "viewed or expired" Terminal Screens

**Audience:** Engineering + Design leadership
**Author:** Lead UX Strategist (synthesis of 6-specialist panel; revised post adversarial review)
**Date:** 2026-06-23
**Status of root cause:** Technical 5xx/network/schema-vs-404 split already shipped (#3424). The *terminal-screen UX* and the *legacy-state data migration* remain open.

---

## 0. Read This First — There Are TWO Components, Not One

This report previously spoke of "the terminal screen" as a single artifact. It is not. Every recommendation below is now scoped to the physical file it edits, because they differ in branding, structure, and button count, and several earlier "fixes" did not land where claimed.

| | **`UnknownSecret.vue`** (RECIPIENT) | **`UnknownReceipt.vue`** (SENDER / receipt) |
|---|---|---|
| Audience | Anonymous, cold, often non-technical | Authenticated owner |
| Branding | Branded-capable (`:branded`, `brandSettings`); **`branded/UnknownSecret.vue` exists** | **Hard-coded `:branded="false"` (line 14); NO `branded/UnknownReceipt.vue` exists** |
| FAQ / "Need help?" modal | Yes (`NeedHelpModal` + `UnknownSecretHelpContent`) | **None** |
| Action buttons | **TWO** co-equal: "Return to home" + "Create a secret" (both `to="/"`) | **ONE**: "Return to home" |
| Headline (h1) | `web.secrets.that_information_is_no_longer_available` = "This secret has been viewed or expired." | **Same visible h1 key**, BUT `aria-label` uses a *different* key: `web.secrets.information_no_longer_available` = "Information no longer available" — a screen-reader/visible-text mismatch |
| SVG `<title>` | Reuses the same h1 key (`...that_information_is_no_longer_available`) — the icon's accessible name is the over-certain sentence | (icon is `aria-hidden`) |

**Consequences that reshape the recommendations:**
- The "two co-equal buttons" paralysis (Q4) and the FAQ rewrites (Q5/Q6) apply **only to `UnknownSecret.vue`**. `UnknownReceipt.vue` already has one button and no FAQ.
- On a custom domain, a **sender** hitting the receipt-terminal screen gets the **unbranded OTS screen** — a brand/trust break that directly violates the "branded custom-domain variants exist" hard constraint. This is a missing item, now S11.
- The owner-resolution split (S4) must specify **which file** the owner lands on and account for the fact that `UnknownReceipt.vue` fires precisely when the receipt record is **absent** — see C8 and the rewritten S4.

---

## 1. Executive Summary

The terminal screens at the end of a one-time link — headline **"This secret has been viewed or expired."** — render a single, over-certain sentence identically for **six mutually exclusive realities**, including the one case where the product *succeeded perfectly*. The defect is not merely that six states share one screen (some collapse is forced by zero-knowledge); it is the **direction of the dishonesty**: the system asserts the *most* certainty ("has been viewed") exactly where it has the *least* knowledge (an anonymous 404 the server cannot disambiguate), while showing the *least* information (the recipient-style screen) exactly where it could hold the *most* truth (the authenticated owner's receipt state). A success — a secret read once and destroyed, the product's only win condition — is dressed in a red circled-x and the word "viewed," which reads to a sender as **interception** and to a cold, often elderly recipient as a **scam or self-inflicted mistake**. Because the over-certain headline contradicts the FAQ's three-way hedge on the same screen, users (correctly) sense the page is lying — and false certainty, not honest uncertainty, is what destroys trust.

Compounding this, the failure modes are **unobservable** (two realities emit no operator signal) and **brittle** (`StatusBadge` *throws* on an unknown state; the dashboard parse is **atomic** — one poisoned row empties the *whole* list), so a real data-poisoning incident hides for weeks inside routine "expired" noise. The fix is not better copy for one screen — it is to **split the two components and their audiences**, **match displayed certainty to actual entropy**, **pull the success case out of the error channel**, and **stop degrading known-valid legacy states into alarm or "unavailable."** The only true *cure* is the still-deferred legacy-state data migration (S8); everything else is mitigation — which we state plainly.

---

## 2. The Core Conceptual Error

**A lossy 6→1 encoding whose headline transmits more certainty than its source entropy permits — and whose certainty points the wrong way per audience.**

Six distinct realities funnel into one `!record` state that renders an over-certain sentence. The screen *asserts* one story ("has been viewed or expired") that the zero-knowledge server provably cannot prove for most of these cases, while a buried FAQ (recipient only) quietly *admits* three possibilities. The page contradicts itself across visual ranks — and a self-contradicting page reads as a lie.

### The six realities, and what each PARTY needs to perceive

| # | Reality | Server actually knows | RECIPIENT (anonymous) should perceive | SENDER (authenticated owner) should perceive | OPERATOR should perceive |
|---|---|---|---|---|---|
| **a** | Expired by TTL | Yes (TTL) | "This link is one-time and is no longer open; this is normal. You did nothing wrong." (no claim of *which* cause) | "Reached its N-day limit; never opened." | Counted as normal-terminal |
| **b** | **Consumed / revealed — SUCCESS** | Yes, on sender path | Nothing ID-specific. Generic "single-use links open only once." Must **not** confirm consumption (timing oracle). | **"Your recipient opened and revealed this; delivered, now permanently deleted."** (positive, timestamp) | **Counted as a positive success event** (so we can measure how often "success" is shown as failure) |
| **c** | Burned by sender | Yes | Same uniform generic copy | "You deleted this before it was viewed." | Counted as normal-terminal |
| **d** | Never existed / typo / truncated URL | Cannot distinguish from a/b/c | Same uniform generic copy + a *generic* "check the link" nudge (shown on ALL terminal 404s) | n/a | Counted (currently emits **no signal**) |
| **e** | Legacy / poisoned `state` bricks a valid secret → 404 | Knows the record existed but state failed `viewable?` | Same uniform generic copy (must not differ — oracle) | Must not silently brick or degrade a *valid* state | **Defect signal** (currently emits **no signal**) |
| **f** | Strict frontend schema rejection of a loadable record | Knows parse failed | Same uniform generic copy | One bad row → placeholder, never empty the whole dashboard | Defect signal (which field/enum) |

**The two halves of the error:**
1. **Over-claiming to the anonymous recipient.** For a 404 the backend raised `MissingSecret` *before building any payload* — it has near-zero bits about which of (a)(b)(c)(d)(e) occurred. The honest answer is uniform uncertainty.
2. **Under-serving the authenticated owner — *when the data is present*.** The sender path normally returns 200 with full receipt state; the owner is *entitled* to ground truth with no oracle risk. But `UnknownReceipt.vue` fires when that state is **absent or unparseable** (e/f), which constrains what S4 can promise — see C8.

---

## 3. Conceptual Challenges (the deep ones)

**C1 — False certainty is the wound, not the cure.** *[All six lenses.]*
"Has been viewed" is a point-estimate over a distribution the server cannot collapse; the agentless passive ("has been viewed" — *by whom? when?*) leaves an empty agent-slot the user's mind fills with its worst fantasy (recipient: "did *I* break it?"; sender: "was I *intercepted*?"). Honest uncertainty owned by the system is a *container* the mind can rest in; false certainty that contradicts the user's experience reads as gaslighting and corrodes trust in the genuinely true copy ("Is it secure? Yes").

**C2 — Success is camouflaged as failure (reality b).** *[All six lenses.]*
The product's one win condition — secret read once, destroyed — is rendered with a red circled-x and "viewed or expired." Color, shape, and valence are all miscoded for the one referent that is a success. **The better the product works, the more "failure" screens it produces.**

**C3 — Two audiences with different entitlements, forced through one signifier.** *[Trust & Safety, Visual-Info, UX Researcher, Support/Ops.]*
The anonymous recipient must learn almost nothing (oracle constraint); the authenticated owner is entitled to exact state and timestamps (their own data). **The honest answer to each is a different fact** — and, as Section 0 shows, a different physical component.

**C4 — Zero-knowledge is being conflated with zero-observability.** *[Support/Ops (lead), Visual-Info, UX Researcher, Trust & Safety.]*
The server cannot read the *secret*, but it can observe *state transitions and parse outcomes*. Realities (b) and (d) emit no operator signal; (e) state-brick is indistinguishable from (a) TTL-expiry in every signal that exists — so MTTD for a poisoning incident is effectively unbounded. Privacy forbids reading the secret, not counting what happened to it.

**C5 — The "Previewed / Revealed / Viewed" lexical collision.** *[UX Researcher, Psychoanalyst, Trust & Safety, Visual-Info, Elderly Caretaker.]*
Three near-synonyms for adjacent states. The sender's awaited plain confirmation ("did they actually get it?") never arrives in plain words. *Note (downgraded from fact to hypothesis per review):* the claim that "Previewed" can persist **forever even after reveal** depends on the backend `previewed→revealed` transition timing, which lives in the Ruby backend and was **not verified in this repo**. Treat "Previewed appears stuck" as a hypothesis to confirm (Open Q4) before investing in S6 copy; if the transition itself is unreliable, that is an upstream bug, not a vocabulary problem.

**C6 — A format glitch is encoded as alarming data loss — and the two halves of the code disagree on what is even valid.** *[All sender-facing lenses.]*
`StatusBadge.vue:25` calls `receiptStateSchema.parse(stateValue)`, which **throws** on an unknown state. Critically, the throw is not the whole story: `StatusBadge` imports `receiptStateSchema` from `schemas/shapes/v3/receipt` — the *canonical-only* schema that **explicitly excludes** `viewed`/`received` ("Deprecated state values ('received', 'viewed') are NOT included", v3 receipt.ts:27-28). Meanwhile `getDisplayStatus` (`status.ts:3`) imports `ReceiptState` from `schemas/shapes/v2`, which **still defines** `VIEWED`/`RECEIVED` and maps them via `STATE_TO_DISPLAY` (status.ts:36,38). So the badge's `parse()` throws on a legacy value *before* `getDisplayStatus`'s alias map (which would have handled it gracefully) is ever reached. The two functions **disagree about whether legacy values are valid** — that divergence, not merely "parse throws first," is the bug surface. (`status.ts:57-59` does fall back to `'orphaned'` for invalid states, but it is unreachable from the badge, and `'orphaned'` is itself glossed "will be destroyed soon" — a format glitch rendered as imminent data destruction.)

**C7 — The word "secret" itself triggers the scam read.** *[Elderly Caretaker, Psychoanalyst.]*
To a non-technical cold recipient, legitimate information is not called a "secret." The word on an unexpected error page, "Create a secret" as a button, and an instruction to message a third party match every scam-awareness lesson. The over-certain headline contradicting the FAQ is, to them, *proof* the page is fake.

**C8 — `UnknownReceipt.vue` fires when the owner's data is ABSENT — which is exactly the data S4 wants to show.** *[New, surfaced in review; Support/Ops, UX Researcher.]*
The receipt-terminal screen renders on `!record` — i.e. when the receipt itself failed to load/parse. In realities (e)/(f) the receipt state is the *very data that failed to parse*. Therefore S4 **cannot promise "Revealed at 14:02" on the failure screen** for those cases — the timestamp is gone. S4 must split into two distinct paths: (i) **state present** (200, valid receipt) → render resolved sender truth *before* ever reaching `UnknownReceipt`; (ii) **state absent/unparseable** (e/f) → a *sender-specific, non-alarming* "We couldn't load this receipt right now (ref: …)" with a defect signal, **not** a fabricated success line. This internal contradiction was unaddressed before.

---

## 4. Practical Challenges by Audience

### RECIPIENT (anonymous, cold, often non-technical) — `UnknownSecret.vue`
- The h1 **"This secret has been viewed or expired."** (also the SVG `<title>`, i.e. the icon's accessible name) is shown **verbatim and false** for typos (d) and bricked-legacy secrets (e); the FAQ's three hedged possibilities contradict it on the same screen.
- A **success (b)** and a **typo (d)** are pixel-identical; the red circled-x signals *error/danger* for what is often the product working perfectly.
- FAQ "What should I do now? *Contact the person who sent you this link... Let them know you weren't able to access the original information*" routes a successful read into an **apology to the sender** — manufacturing embarrassment, a false alarm, and possibly a duplicate secret. It is also a phishing-shaped instruction.
- **Two co-equal buttons** — "Return to home" and "Create a secret" (both `to="/"`) — both ask the recipient to do the *system's* job. (This is specific to `UnknownSecret.vue`; the sender's `UnknownReceipt.vue` already has a single button.)
- No "you did nothing wrong," no anti-phishing reassurance; the typo case (d) gets no "check the link" nudge.

### SENDER (authenticated owner) — `UnknownReceipt.vue` + dashboard
- The owner can be dropped onto a recipient-style "no longer available" screen that answers **none** of the sender's real fears (intercepted? compromised? who viewed it, and when?). Note this screen is **`UnknownReceipt.vue`** (one button, no FAQ, hard-coded unbranded), *not* the recipient component.
- The receipt h1 has an **aria-label / visible-text mismatch** (`information_no_longer_available` spoken vs `that_information_is_no_longer_available` shown) — a real accessibility defect with no current fix.
- `StatusBadge` throws on unknown state via the v3 schema; the v2 alias map that would have rendered a *valid* legacy `viewed`/`received` is bypassed.
- **Atomic** dashboard parse: `receiptListStore.fetchList` runs one `gracefulParse` over the *entire* response; on failure it sets `records = []`, `details = {}`, `count = 0` — an **empty** dashboard (not `null`). One legacy/poisoned row empties everything.

### OPERATOR / SUPPORT
- **No correlation id, no opaque code** on either `Unknown*` screen. Every ticket starts with "send me a screenshot."
- The 404 carries **no machine-readable reason sub-code** — a `viewable?` state-reject (e) is indistinguishable from a record-absent 404 (a/b/c/d).
- Realities (b) success, (c) burned, (d) typo emit **no signal**; there is **no positive success counter** anywhere for reality (b).
- The legacy rename (viewed→previewed, received→revealed) has **no data migration**, so a known, countable population of legacy rows deterministically bricks — with no counter on it. (Confirmed: v2 keeps the aliases, v3 drops them, nothing migrates stored data, and the backend `viewable?` gate / v3 receipt enum still reject the legacy values.)
- The shipped #3424 404-vs-error split rests on a **fragile dual-type comparison**: `BaseShowSecret.vue:45` checks `errorCode === 404 || errorCode === '404'`, fed by `useSecret.ts:60` `errorCode = err.code ?? null`. Any error path that sets a differently-typed or missing code silently misroutes a real 404 into the retryable-error screen (or vice-versa).

---

## 5. Principles for the Redesign (decision rules)

1. **Success must never look like failure.** A completed one-time view is the product succeeding; never a red circled-x, never the error channel. Where the system *can* know it succeeded (sender path, state present), say so affirmatively.
2. **Honest uncertainty beats false certainty.** Displayed certainty must match the server's actual entropy. For the anonymous 404: one neutral statement that asserts *that* the link is terminal, never *which* of six things happened or *who* did it.
3. **The authenticated owner is entitled to more — but only when the data is present.** Resolve the owner *up* to full state/timestamps when the receipt loaded (S4 path i); when it failed to load (e/f), give a non-alarming sender-specific failure, not a fabricated success.
4. **Never build an oracle — and "oracle" includes timing, size, and 1-bit class.** The anonymous response must be indistinguishable across (a)(b)(c)(d)(e) not only in *text* but in *status, body size, and timing*. Any per-ID nudge must appear on *all* terminal 404s. **No visible reason class — not even binary** — may be rendered to an anonymous visitor (see S2).
5. **One clear next action, framed as help not homework** (recipient component only). Replace the two-useless-button paralysis with a single dignified action; remove the scam-shaped "go confess you failed."
6. **Dignified, plain language; "you did nothing wrong."** Lead with the benign base rate, defuse the scam read, soften "secret" → "secure message," name the service.
7. **Zero-knowledge ≠ zero-observability.** Instrument state transitions, parse outcomes, *and successes*.
8. **Graceful degradation must preserve meaning, not erase it.** A format glitch encodes as low-salience uncertainty, never alarm, never catastrophic blast radius — **and a known-valid legacy state must render its true meaning via the alias map, not degrade to "unavailable."**

---

## 6. Prioritized Opportunities

Ordered by impact ÷ effort. Tags: **[Audience]**, **Effort**, **Component**, **Oracle note** where it changes the anonymous recipient view.

### QUICK WINS

**Q1 — Rewrite the over-certain headline to honest uncertainty.** *[Recipient | Low | `UnknownSecret.vue` h1 + SVG `<title>`, AND `UnknownReceipt.vue` h1 + its mismatched aria-label]*
Change `web.secrets.that_information_is_no_longer_available` from
> "This secret has been viewed or expired."

to a single true-for-all-six statement, e.g.
> "This link can only be opened once — and it can no longer be opened."

with blameless subtext: *"This usually means the information was already read, or the link expired. **You haven't done anything wrong.**"*
**This touches at least two keys, not one:** the h1/`<title>` key *and* `UnknownReceipt`'s divergent aria-label key `web.secrets.information_no_longer_available` (fix the aria/visible mismatch while here).
**Oracle note: SAFER than today** — one uniform sentence for every reality leaks strictly *less* than the current two-option guess; must look identical whether the ID existed or not.

**Q2 — Kill "viewed" on every anonymous surface.** *[Recipient | Low | `UnknownSecret.vue`]*
"Viewed" is a human-behavior claim the server cannot make and the precise word that triggers interception panic. Use "accessed or expired" only in the hedged FAQ; never assert a human read it. **Oracle note:** neutral — changes implied certainty, not disclosure.

**Q3 — Re-icon / recolor the terminal state from error to neutral-terminal.** *[All | Low-Med | both `Unknown*` components]*
Replace the red circled-x / red `question-mark-circle` with a neutral "closed/expired envelope" mark in a non-alarm color, on **both** files (`UnknownReceipt.vue:18-22` is a red `question-mark-circle`). The post-#3424 retryable alert stays red, preserving the genuine-error channel. **Oracle note:** neutral styling reveals nothing about which reality occurred.

**Q4 — Replace the two useless buttons with one helpful action.** *[Recipient | Low-Med | `UnknownSecret.vue` ONLY]*
Drop **"Create a secret"** and demote **"Return to home"** for the recipient. Single primary action: **"Ask for a new link"** opening a prefilled message (*"Hi — the secure link you sent me has already been used. Could you send a fresh one? Thanks."*). **Scope note:** `UnknownReceipt.vue` already has a single "Return to home" button — Q4 does **not** apply there. **Oracle note:** identical for every terminal case; no per-ID info.

**Q5 — Add explicit anti-phishing + base-rate reassurance, promoted out of the modal.** *[Recipient | Low | `UnknownSecret.vue` + `branded/UnknownSecret.vue`]*
Lead-visible: *"This is a normal page from Onetime Secret, a service for sharing information securely. Links here always stop working after one use — that's by design."* **Scope note:** `UnknownReceipt.vue` has no FAQ/modal; this is recipient-only. **Oracle note:** purely generic product behavior; safe; must also land on the branded recipient variant.

**Q6 — Make the recipient FAQ action state-honest, not apology-shaped.** *[Recipient | Low | `UnknownSecretHelpContent.vue`]*
Gate the recovery action behind the user's own expectation: *"If you were expecting to read something here, ask the sender for a new link."* **Scope note:** recipient FAQ only. **Oracle note:** neutral.

**Q7 — A generic "check the link" nudge for the typo case (d).** *[Recipient | Low | `UnknownSecret.vue`]*
*"If you copied this link by hand, check it matches the one you were sent — links are long and easy to clip."*
**Oracle note — now fully specified (was punted):** the nudge must (i) appear on **ALL** terminal 404s, worded as a maybe; (ii) be present **only on the anonymous recipient screen** so its presence cannot be cross-referenced against the owner-resolved screen to differentiate populations (the owner screen is a separate component reached via auth, so this is structurally satisfied as long as the anonymous screen is invariant); and (iii) **not change response timing or byte-size** — it is static template text shipped to every 404, never conditionally fetched. The full byte-/timing-identity audit is Open Q5, but the design constraint is now stated, not deferred.

**Q8 — `StatusBadge`: graceful-degrade THROUGH the alias map, not to "unavailable."** *[Sender | Low | `StatusBadge.vue` + `status.ts`]*
Replace `receiptStateSchema.parse(stateValue)` (line 25, which throws) with a non-throwing path that **routes the raw value through `getDisplayStatus`'s v2 alias map first** (which correctly maps `viewed→previewed`, `received→revealed`). Only a value unknown to *both* schemas falls back to a neutral **"Status unavailable"** badge with a `statusbadge.unknown_state` warn. **Rationale (corrected per review):** a bare `safeParse`→"Status unavailable" would degrade a *perfectly valid, known* legacy state to "unavailable" — arguably worse than today. Do **not** route unknowns to "orphaned / will be destroyed soon." **Oracle note:** sender-only, n/a.

**Q9 — Add interception reassurance on the authenticated sender surface only.** *[Sender | Low | sender receipt view, state present]*
On "Revealed": *"Opened once and revealed, then permanently deleted. A single-use link can only be revealed one time."* **Oracle note: SAFE because owner-only** — never put view-timing reassurance on the anonymous screen.

### STRUCTURAL CHANGES

**S1 — Server-side reason sub-code on the 404 path (logged, not shown).** *[Operator | Low | backend]*
Tag the raised `MissingSecret` 404 with `reason=state_reject` when `viewable?` fails on state vs `reason=absent` when the record is gone; export as a metric dimension. **This single dimension separates (e) from (a/b/c/d) — the core blindness — at zero user-facing cost.** **Oracle note:** log/metric only, never in the response body. *Highest leverage per unit effort.*

**S2 — Opaque, request-scoped correlation id — and NO visible reason class.** *[Operator/Recipient | Med | both `Unknown*` components + backend]*
Render a small "Reference: 8F2K…" — a random *per-request* id (not derived from the secret id). Log the full reason class server-side keyed by that id. **Corrected per review:** drop the previously-proposed *visible* binary `{normal-terminal | technical-error}` class entirely. Even one bit is an oracle: if `technical-error` ever correlates with reality (e) (a legacy-bricked record that *existed*), a prober learns "this ID hit the backend record path" vs "absent" — exactly the existence oracle Principle 4 forbids. The only token safe to render to an anonymous visitor is the **opaque, classless request id**; the reason class lives server-side only, retrievable by support via the id. **Oracle note:** id must be request-scoped with no derivable link to the secret id; no class on screen, ever.

**S3 — Counters + alerts: `secret.404.state_reject` and `dashboard.parse_empty`.** *[Operator | Med | backend + store]*
Turn lagging ticket volume into a leading signal; page on-call when either exceeds baseline. (Renamed from `parse_null` → `parse_empty` to match the store's actual `records = []` failure assignment.) **Oracle note:** aggregate counts only.

**S3b — Positive success counter for reality (b).** *[Operator | Low-Med | backend, on the `viewable?`→`previewed`/reveal path]*
**New (gap in prior draft):** Open Q3 names "share of terminal screens correctly attributed" as the success metric, but no opportunity instrumented it. S1 only splits `state_reject` vs `absent` on *failures*. Add an explicit **success event** counted when a secret is successfully served and consumed (the `previewed`/reveal transition), so reality (b) is measurable as a *positive* outcome distinct from failures — the denominator that makes "is success shown as failure?" answerable. **Oracle note:** aggregate, server-side; no per-ID emission.

**S4 — Owner-aware terminal handling — split by whether receipt data is PRESENT.** *[Sender | Med | sender receipt route + `UnknownReceipt.vue`]*
**Corrected per C8** (prior draft assumed the failing screen still had the data it failed on):
- **Path (i) — receipt state present (200, valid):** resolve the owner *before* `UnknownReceipt` is ever reached. Revealed → *"Your recipient opened this — delivered and now deleted"* (positive, with the timestamp the receipt holds); Burned → *"You deleted this before it was viewed"*; Expired → *"Reached its N-day limit; never opened."*
- **Path (ii) — receipt state absent/unparseable (e/f):** the data needed for path (i) is gone, so do **not** fabricate a success line. Render a sender-specific, non-alarming *"We couldn't load this receipt right now (ref: …)"* and emit the defect signal. This is the corrected role of `UnknownReceipt.vue`.
**Oracle note: owner-only, gated strictly on receipt ownership** — never reachable anonymously; the anonymous recipient screen is unchanged.

**S5 — Per-row resilient dashboard parsing — a SCHEMA-SHAPE change, not a wrapper.** *[Sender/Operator | Med-High | `receiptListStore.ts` + response schema]*
**Corrected per review:** `fetchList` runs a **single atomic `gracefulParse`** over the entire response (`receiptListStore.ts:90`); there is **no per-row loop to wrap**. Achieving per-row resilience requires changing the response *schema* so rows parse independently — e.g. `z.array(receiptListSchema.catch(fallbackRow))` or iterating rows and parsing each — so a bad row renders a single "Couldn't display this record (ref: …)" placeholder instead of emptying `records`/`details`/`count`. Increment a per-row counter tagged with the offending enum value. Scope this as a schema refactor, not a localized try/catch. **Oracle note:** sender-only.

**S6 — Fix the sender vocabulary: relabel the EXISTING keys into a delivery timeline.** *[Sender | Med | `web.STATUS.*` + `STATE_TO_DISPLAY`]*
Present sender state as a progression — **Created → Opened → Revealed → Destroyed** — with plain glosses. **Resolved per review:** prefer **relabeling the already-localized `web.STATUS.*` keys and reusing the `STATE_TO_DISPLAY` map** (cheap; reuses existing 10-key namespace and locale coverage) over net-new lifecycle keys (expensive; competes with S9's localization wave). If a true new label is unavoidable, batch it into the S9 wave. Gate on confirming the `previewed→revealed` transition is reliable (Open Q4, C5) before investing. **Oracle note:** owner-only.

**S7 — Prime the one-time mental model at PREVIEW, before consumption.** *[Recipient | Low-Med | valid preview screen]*
On the valid preview screen: *"This is a single-use secure message — once you reveal it, it disappears for everyone."* **Oracle note:** shown only after a valid secret loads — reveals nothing about non-existent IDs.

**S8 — Ship the deferred legacy-state data migration (instrumented). THE ONLY CURE.** *[All | Med-High | backend + schemas]*
Migrate stored `viewed→previewed`, `received→revealed`, and/or accept legacy values in **both** the backend `viewable?` gate **and** the v3 receipt enum during transition. **Before** migrating, emit a count of affected rows to size the bricked population. This is the only fix that removes realities (e)/(f) at the *source*; without it, every copy fix above is mitigation, not cure. Keep S5's per-row resilience and Q8's alias-routing as the permanent safety net. **Oracle note:** makes genuinely-valid secrets viewable again; no disclosure change.

**S9 — Soften "secret" → "secure message / information" in recipient copy.** *[Recipient | Med (40+ locales) | recipient surfaces]*
High emotional payoff for the non-technical cold recipient; "secret" is the single most scam-triggering word. Sequence as a deliberate localization wave after higher-impact items.

**S10 — Support runbook keyed to the reference id.** *[Operator | Low | docs]*
"Ticket says no longer available → ask for the reference id → look up the server-side reason class → `technical-error` family escalates as a defect with the log line; `normal-terminal` gets create-new guidance." Deterministic triage the day S2 ships. (Note: the class is *retrieved server-side by id*, never read off the screen — consistent with S2's no-visible-class correction.)

**S11 — Create a branded `UnknownReceipt` variant (or remove the hard-coded `:branded="false"`).** *[Sender | Med | new `branded/UnknownReceipt.vue` + route]*
**New (hard-constraint violation the prior draft missed):** there is `branded/UnknownSecret.vue` but **no** `branded/UnknownReceipt.vue`, and `UnknownReceipt.vue` hard-codes `:branded="false"` (line 14). On a custom domain, a **sender** hitting the receipt-terminal screen sees the unbranded OTS screen — a brand/trust break that violates the "branded custom-domain variants exist" constraint. Add a branded receipt variant or make `UnknownReceipt` brand-aware like its sibling. **Oracle note:** owner-only; n/a.

**S12 — Normalize / type-guard the #3424 404 comparison.** *[Operator/Recipient | Low | `useSecret.ts` + `BaseShowSecret.vue`]*
**New (the shipped split this report builds on is fragile):** `BaseShowSecret.vue:45` checks `errorCode === 404 || errorCode === '404'` against `errorCode = err.code ?? null` (`useSecret.ts:60`). Normalize `err.code` to a single type at the source (e.g. coerce to number, or a typed `isNotFound` helper) and add a test, so no error path can misroute a real 404 into the retryable channel (or vice-versa). The entire honest-error split rests on this comparison. **Oracle note:** neutral — fixes routing reliability, not disclosure.

### Sequencing recommendation
Land **Q1, Q2, Q4, Q6, Q7** (recipient copy/action honesty — one locale batch, `UnknownSecret.vue`), **Q1's aria fix on `UnknownReceipt.vue`**, **S1** (the one log dimension), **S3b** (success counter), and **S12** (404 normalization) first: highest trust/observability return for least cost. Then **Q3, Q8, Q9, S2, S3, S10, S11** (iconography, alias-safe badge, classless reference id, alerting, runbook, branded receipt). Then the structural audience split **S4, S5, S6, S7**. Schedule **S8** (migration) as its own instrumented change and **S9** (the "secret" rename) as a deliberate localization wave.

---

## 7. Open Questions / What to Validate With Real Data

1. **How often is the terminal screen a success (b) vs a 404-on-nothing (d) vs bricked-legacy (e)?** Unmeasurable today. S1 + S3 + **S3b** must ship *before* any copy change can be called "working."
2. **How large is the still-bricking legacy population, and on which path?** S8's pre-migration count answers "how big is the incident already?" Validate whether the backend `viewable?` gate and the v3 receipt enum *both* still reject `viewed`/`received` (confirmed they do in the TS; the gate is Ruby) — this determines whether a data migration alone suffices or whether the gate/enum must also accept legacy values during transition.
3. **Success definition:** success is *the share of terminal screens correctly attributed by the viewer*, not "fewer terminal screens." Operationalize as ↓ post-(b) duplicate-secret creations; ↓ sender tickets containing "intercepted/compromised/hacked"; ↑ recipient preview→reveal completion; and (d)/(e) as **separately counted** metrics.
4. **Does "Previewed" actually persist after reveal?** This is a **hypothesis, not a verified fact** — the `previewed→revealed` transition is in the Ruby backend, unverified here. Confirm before investing in S6; if the transition is unreliable, it is an upstream bug.
5. **Oracle audit of the recipient screen post-change:** verify the response is **byte-identical (status, body size, timing)** across (a) expiry, (b) success, (d) never-existed, (e) bricked — including the Q7 nudge, which must appear unconditionally and add no conditional fetch. Confirm S2's reference id is request-scoped with no link to the secret id, and that **no reason class is rendered**.
6. **Cold-recipient comprehension test (incl. elderly / non-technical):** does the rewritten `UnknownSecret.vue` read as legitimate-and-normal rather than scam-or-self-blame? Validate Q5 anti-phishing, Q1 "you did nothing wrong," and the single Q4 action.
7. **Branded variants:** confirm every recipient-facing change renders on `branded/UnknownSecret.vue`; and **resolve S11** — the receipt screen has *no* branded variant, so a custom-domain sender currently sees unbranded OTS chrome. Verify the owner split (S4) and the absence of any branded receipt do not leak or break on custom domains.

---

## Changes from review

- **Added Section 0 and a per-component scope to every opportunity.** The prior draft conflated `UnknownSecret.vue` (recipient: branded-capable, FAQ, two buttons) and `UnknownReceipt.vue` (sender: hard-coded unbranded, no FAQ, one button). Q4/Q5/Q6 are now scoped recipient-only; the "two-button paralysis" is no longer implied for the sender screen.
- **New S11:** flagged the missing `branded/UnknownReceipt.vue` (hard-constraint violation) — a custom-domain sender currently sees unbranded chrome.
- **Q1 expanded to ≥2 keys** and now fixes the `UnknownReceipt.vue` aria-label/visible-text mismatch (`information_no_longer_available` vs `that_information_is_no_longer_available`), a previously-unnoted accessibility defect.
- **S2 corrected:** dropped the visible binary reason class entirely — even 1 bit tied to record-existence is an oracle. Only an opaque, classless request id is rendered; the class stays server-side. Principle 4 and S10 updated to match.
- **S4 corrected (C8 added):** `UnknownReceipt.vue` fires when receipt data is *absent*, so it cannot show "Revealed at 14:02" for (e)/(f). Split into path (i) state-present (resolve before the failure screen) and path (ii) state-absent (non-alarming failure, no fabricated success).
- **S5 corrected:** `gracefulParse` is a single atomic `safeParse`; there is no per-row loop. Reframed as a schema-shape change (`z.array(...catch...)`/iteration), not a wrapper. Failure assignment is `records = []` (empty), not `null` — `parse_null` renamed `parse_empty` (S3).
- **Q8 corrected:** route unknown states through `getDisplayStatus`'s v2 alias map first (so a valid legacy `viewed`/`received` renders correctly), falling back to "Status unavailable" only for truly-unknown values — instead of degrading known-valid states to "unavailable."
- **C6 deepened:** named the two-source divergence — `StatusBadge` uses v3 (legacy excluded → throws) while `getDisplayStatus` uses v2 (legacy retained). The unreachability is a *schema disagreement*, not just ordering.
- **New S3b:** added a positive success counter for reality (b); the prior draft named the metric in Open Q3 but instrumented only failures.
- **New S12:** flagged the fragile `errorCode === 404 || errorCode === '404'` dual-type comparison underpinning the shipped #3424 split; recommended normalization + a test.
- **C5 and the sender bullet downgraded** the "Previewed persists forever even after reveal" claim from fact to hypothesis (backend transition unverified in this repo), aligning with Open Q4.
- **S6 reconciled** with the existing `web.STATUS.*` namespace and `STATE_TO_DISPLAY`: prefer relabeling existing keys (cheap) over net-new copy (expensive), and acknowledged interaction with S9's localization cost.
- **Open Q5 strengthened:** the oracle audit now requires byte-/size-/timing-identity, not just text, and explicitly checks the Q7 nudge and the classless reference id.
