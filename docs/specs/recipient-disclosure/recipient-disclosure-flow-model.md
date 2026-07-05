# The recipient surface as an information-flow channel (formal model)

Formal companion to `docs/specs/recipient-disclosure/recipient-disclosure-matrix.html`. That document
is the design source of truth in prose; this one captures the same
"who-may-distinguish-what-without-it-leaking" logic in a single, established
formalism so the policy is **machine-checkable** rather than argued case by case.

The canonical artifact is the channel matrix in §4. Everything else — the
philosophical principle, the disclosure matrix, the five invariants, the gaps
F1–F11, and the client-side opportunities A1–A6 — is a statement *about that
matrix*.

---

## 1. Why a formalism exists for this

What we built by hand (which observer may distinguish which outcomes, under
which conditions, without the distinction leaking) is the canonical object of
**information-flow security**. The same structure was discovered independently in
four fields; this is the cross-disciplinary "prior art" the model rests on.

| Field | The structure | The "no oracle" condition |
|---|---|---|
| **Info-flow security / CS** | Goguen–Meseguer **noninterference** (1982); Denning's **lattice model of secure information flow** (1976); Bell–LaPadula (1973); Myers–Liskov **Decentralized Label Model** (per-principal reader sets, 1997); Landauer–Redmond **"A Lattice of Information"** (1993) — elements *are* partitions, ordered by refinement | the secret is constant on every cell of the low observer's view |
| **Cryptology** | **indistinguishability** (IND-CPA games); simulation / ideal-functionality; the "decryption/padding oracle" | two worlds the adversary provably cannot separate |
| **Epistemic logic / economics** | **Aumann information partitions** (1976); Kripke accessibility relations (Fagin–Halpern–Moses–Vardi, *Reasoning About Knowledge*, 1995) | the agent does not *know which* world holds (its cell is non-singleton) |
| **Statistics** | **differential privacy** (Dwork 2006) & **membership inference** (Shokri et al. 2017) = the existence oracle; **k-anonymity / l-diversity / t-closeness** & statistical disclosure control — equivalence classes by generalization/suppression | the released view is ε-close whether or not a given record exists |

The modern synthesis that unifies the qualitative (partition) and quantitative
(how-many-bits) views is **Quantitative Information Flow (QIF)** — Clark–Hunt–
Malacaria; Smith, *On the Foundations of QIF* (2009, min-entropy leakage); Alvim,
Chatzikokolakis, McIver, Morgan, Palamidessi, Smith, *The Science of Quantitative
Information Flow* (2020). Its data structure is a **channel matrix**
`C : Secret → Δ(Observation)`, equipped with a **refinement order** on channels
and **g-leakage** (gain functions) to weight different adversary goals. The
boolean noninterference case is the special case where leakage is exactly 0.

We adopt the QIF channel + its induced **Lattice-of-Information partition** as the
one format.

---

## 2. The secret (high) variables

- `X` — *which world obtains*, the metadata variable:
  `Ω = { V, a, b, c, d, e, f }`
  - `V` viewable → 200 (a secret is present to reveal)
  - `a` expired · `b` consumed/revealed (**success**) · `c` burned ·
    `d` never-existed/typo · `e` bricked internal state (valid, never-consumed,
    404'd) · `f` client schema rejection
- `Σ` — *the secret's plaintext*, the payload variable. Distinct confidentiality
  requirement; used only by F6–F8 and A3 below.

The whole policy concerns leakage of `X` (and separately `Σ`) to each observer.

---

## 3. The observers (a lattice of channels)

Each observer is a channel `C_obs : X → Δ(Obs)` and, equivalently, an
**indistinguishability partition** `Π_obs` on `Ω` (two worlds share a cell iff
that observer cannot tell them apart). The observers are partially ordered by how
much they may learn (a clearance lattice):

```
            Π_op  (operator / server logs)        ── authorized, server-side
              │
            Π_owner (authenticated sender)         ── authorized, behind auth
              │
   Π_recip  (anonymous recipient + private S)      ── conditioned by local side-info
              │
   Π_anon  ≈  Π_net   (anonymous HTTP reply ; on-path / CDN observer)   ── must learn ~nothing
```

Plus the off-axis channels that gaps exploit: `C_rcptHolder` (anyone holding a
`receiptExtid`, via `POST /api/v3/guest/receipts`), `C_url` (the link in
history/Referer/CDN logs), `C_client@rest` (DOM/clipboard/bfcache/localStorage).

---

## 4. The canonical artifact — the channel / partition matrix

Two worlds sharing a **label** in a column means that observer **cannot
distinguish** them. The policy is a predicate over this matrix (§5).

| world `x` | `Π_anon` (HTTP) | `Π_net` (on-path) | `Π_recip` (+ private `S`) | `Π_owner` (authed) | `Π_op` (logs) |
|---|---|---|---|---|---|
| `V` viewable  | `R` | `R` | `R` | `V` | `V` |
| `a` expired   | **`⊥`** | `⊥` | `⊥` | `a` | `a` |
| `b` consumed ✓| **`⊥`** | `⊥` | **`✓`** *iff* `S`="I opened it" | `b` | `b` |
| `c` burned    | **`⊥`** | `⊥` | `⊥` | `c` | `c` |
| `d` never-existed | **`⊥`** | `⊥` | `⊥` | — | `d` |
| `e` bricked   | **`⊥`** | `⊥` | `⊥` | `e` | **`e` (defect)** |
| `f` schema-reject | **`⊥`** | `⊥` | `⊥` | `f` | **`f` (defect)** |

- `Π_anon`/`Π_net`: all six realities carry `⊥` → one protected cell. The single
  legitimate distinction is `R` (reveal) vs `⊥` (terminal). Note `b` and `d`
  share `⊥` — that identity *is* the existence/surveillance oracle being closed.
- `Π_owner`/`Π_op`: discrete → authorized full disclosure (a higher node in the
  lattice; not an oracle because it is reached only through auth / server-side).
- `Π_recip`: equal to `⊥` **except** `b` may split to `✓` — see §6.

### The machine-checkable encoding

`C_anon` in the **target** design, as the invariant tuple every non-viewable
world must share:

```yaml
# C_anon : X -> Observation        (target / oracle-free design)
# Coordinates that MUST be identical across the protected cell {a,b,c,d,e,f}:
coordinates: [http_status, body_bytes, response_size, timing_bucket,
              header_set, side_effect, request_emitted, third_party_fanout,
              branding]

rows:
  V: { http_status: 200, ... }                 # the ONE allowed distinction: reveal vs terminal
  a: &cell_terminal
     { http_status: 404, body_bytes: B0, response_size: N0, timing_bucket: T0,
       header_set: H0, side_effect: none, request_emitted: true,
       third_party_fanout: F0, branding: generic }
  b: *cell_terminal
  c: *cell_terminal
  d: *cell_terminal
  e: *cell_terminal
  f: *cell_terminal

# Noninterference (the entire "five invariants", in one line):
assert NI:  ∀ x,x' ∈ {a,b,c,d,e,f}:  row(x) == row(x')
#   ⇔  I(X ; C_anon | ¬viewable) = 0
#   ⇔  min-entropy leakage  L(X → C_anon | ¬viewable) = 0
```

A **gap** is a coordinate on which some row diverges (`assert NI` fails). An
**opportunity** is a refinement of `Π_recip` only, that never touches `C_anon`.

---

## 5. The policy as one predicate

> For every observer `obs`, the value of `X` restricted to `{a,…,f}` must be
> **constant on each cell of `Π_obs`**, except where `obs` is authorized
> (`owner`, `op`).

Equivalently in QIF terms: the min-entropy (or Shannon) leakage of `X` through
`C_anon` and `C_net`, conditioned on `¬viewable`, is **0**. Quantitatively, score
any residual divergence with **g-leakage** under two gain functions:

- `g_exist` — adversary goal: *did this ID ever exist?* (collapses `{a,b,c,e,f}`
  vs `{d}`)
- `g_view`  — adversary goal: *was it viewed, and when?* (collapses `{b}` vs the
  rest, and the temporal variant)

A change is admissible iff `V_{g_exist}` and `V_{g_view}` (the adversary's
expected gain) are unchanged from the no-information prior.

---

## 6. Opportunities as conditioning; the two failure modes

The recipient's local store `S` (A1/A2/A6) is **private side-information** that
refines `Π_recip` but **not** `Π_anon`:

```
Π_recip  =  Π_anon  ⊓  Π_S          (refine the recipient's own view by S)
Π_anon   =  unchanged               (S is emitted by no adversary-readable channel)
⇒ admissible:  the b → ✓ split lives only in the recipient's browser.
```

This is the formal content of **"client-side disclosure ≠ server oracle."** It
holds **iff** the safety rails keep `S` out of every adversary-readable channel.

### 6a. The combination oracle = the Lattice-of-Information **join**

When `S` is made *server-verifiable*, it stops being private conditioning and
becomes a channel. The adversary's view is then the **join** (`∨`, the
coarsest-common-refinement in the Lattice of Information):

```
Π_adv  =  Π_anon  ∨  Π_{A2-server}  ∨  Π_F9  ∨  Π_request-presence
       ⊐  ⊥        (strictly finer than the protected cell)
       ⇒ separates "I consumed it"  from  "someone else consumed it"
         (the intended-vs-actual-recipient oracle)
```

"Oracle-safe in isolation, unsafe in combination" is *exactly* the statement that
the LoI join of nodes can sit strictly above each component. The formalism
**predicts** the empirical finding: evaluate any recipient feature as the join
with `C_rcptHolder` (F9) and request-presence, never standalone.

### 6b. A3 (client-side plaintext digest) = high min-entropy leakage of `Σ`

A3 stores `g = digest(Σ)`. For low-entropy payloads (`H∞(Σ)` small — PIN, OTP,
seedphrase, `sk-…`/`ghp_…` token, short password), the client-at-rest channel has

```
L∞(Σ ; g)  ≈  H∞(Σ)            # offline guessing inverts g; salt is co-located
```

i.e. `g` is a **near-lossless channel for the payload** to a forensic/eDiscovery
observer, *past the sender's TTL*. It violates a different invariant
(`Σ`-confidentiality, not `X`-metadata), which is why it is categorically worse
and **dropped unconditionally** rather than constrained.

---

## 7. Gaps F1–F11 as assertion failures over `C_anon`

| Gap | Breaks | Formal effect | Status |
|---|---|---|---|
| **F1** | `side_effect` | probing mutates `X` (`new→previewed`): the channel has **feedback/memory** → an adaptive 2-probe **strategy** refines `Π_anon` over time (Wittbold–Johnson *nondeducibility on strategies*, 1990) — not memoryless NI | **CLOSED** — #3633 (PR #3635, 2026-07-04): GET is lifecycle-safe; `side_effect: none` holds; the channel is memoryless again |
| **F2** | `http_status` | `⊥` splits: `{a,b,c,d}` \| `f→422` \| `disabled→403` \| `lockout→429` | High |
| **F3** | `timing_bucket` | splits `{exists + passphrase}` from `{d}`; a `429` lockout is reachable only from a real protected ID | High |
| **F4** | `request_emitted` | the terminal screen requires a live XHR whose status carries F2; the "render-before-404" A1 variant toggles this coordinate | High |
| **F5** | `branding` | brand resolved from host *before* viewability → branded chrome for any id confirms tenant-on-host | Med |
| **F6** | channel `C_url` (leaks `Σ`) | the URL *is* the bearer secret; leaks via history / `Referer` / CDN logs | High |
| **F7** | channel `C_client@rest` (leaks `Σ`) | bfcache / back-button re-renders plaintext after server destruction | High |
| **F8** | channel `C_client@rest` (leaks `Σ`) | plaintext lingers in DOM / clipboard / password manager | Med-High |
| **F9** | channel `C_rcptHolder` | `POST /guest/receipts` returns `is_revealed` etc. to a receipt-id holder → a near-discrete partition; an existence/surveillance channel if the id is guessable or link-derivable | High |
| **F10** | `third_party_fanout` | Sentry/analytics/branded-asset fetches fire on one branch but not the other → a network observer separates the cell by *which* requests fire | Med |
| **F11** | `side_effect` (cross-boundary) | link-preview / AV bots fetch in transit and spend the one view → F1 escalated across the email boundary | **PARTIAL** — passive fetch spends nothing since #3633; the reveal is still `GET…continue=true`, not a human-gated POST (A4) |

(All other rows re-verified open against `main`, 2026-07-04. Sev unchanged:
F2–F4, F6, F7, F9, F11 High; F5, F8, F10 Med.)

Each row is a failing instance of `assert NI` (F2–F5, F10), a feedback/strategy
violation (F1, F11), or a leak of `Σ` on a different channel (F6–F8) / a non-`anon`
channel that must be folded under the same predicate (F9).

### 7a. Closure order, and the `Π_op` preservation constraint

The gaps close in dependency order, consolidated 2026-07-04 (prose version in
the matrix's "Sequencing" section): **0** side-effects (F1 ✓) → **1** server
row-equality (F2, F3) → **2** client coordinates (F4/F5/F6/F10) → **3** off-axis
channels (F9, F11/A4) → **4** the `Σ` channels (F7/F8) → **5** semantics + the
data cure. Memory first, because feedback defeats memoryless NI fixes; server
before client, because `C_anon`'s client-side coordinates can only be as uniform
as the row they render.

The non-obvious constraint is on the **authorized** channel: the policy requires
`Π_op` to stay **discrete** (§4 — the operator is entitled to full disclosure,
including the defect worlds `e`, `f`). A fix that flattens `C_anon` rows without
adding an operator-side channel also flattens `Π_op` — driving
`I(X ; C_op | ¬viewable) → 0` for the one observer where leakage is *required*.
That is a policy violation in the opposite direction, and operationally it makes
defect-world MTTD unbounded. Hence the coupling rule:

> **Every change that removes a coordinate from `C_anon` must, in the same
> change, add an equivalent coordinate to `C_op`** (a logged reason sub-code, a
> per-reality counter — including a positive counter for `b`). The two channels
> move in lockstep, in opposite directions.

`assert NI` for `C_anon` and `assert discrete(Π_op)` are therefore a **pair**;
CI should check both, or the first will be satisfied by quietly breaking the
second.

---

## 8. The safety rails as channel constraints

The A-series is admissible **iff all of these hold** — each keeps `S` from
entering `C_anon`, `C_net`, or `C_rcptHolder`:

1. **Never server-verifiable** — `S` feeds no endpoint (else it joins `C_rcptHolder`; §6a).
2. **Always still call the server** — `request_emitted` stays `true` on re-visit; render the hint from the uniform reply (else `request_emitted` becomes a coordinate that splits `⊥`).
3. **Separate namespace, opaque key** — `S` is keyed to an opaque local token, never the link-derivable id.
4. **Status only, never content or digest** — kills A3 (`L∞(Σ;·)=0`).
5. **Default ephemeral** — `sessionStorage` by default; `localStorage` only on explicit opt-in.
6. **TTL + count-capped + one-tap erase, disclosed** — durable client persistence is PII (GDPR notice/erasure).

---

## 9. How to use this

- The model is **falsifiable**: any proposed change is admissible iff it preserves
  `assert NI` for `C_anon`/`C_net`, leaves `L∞(Σ ; ·)=0` on the client/URL
  channels, and does not refine the adversary join (§6a).
- It is **machine-checkable in principle**: encode each route's response as the
  coordinate tuple in §4 and assert row-equality across `{a..f}`; encode the
  receipts endpoint as `C_rcptHolder` and assert constant-time + unguessable-id;
  add the join check (§6a) to CI for any client-side receipt feature.
- It gives the team a **shared vocabulary** (cell, refinement, join, leakage,
  side-information) instead of re-litigating each feature in prose.

## References

- D. Denning, *A Lattice Model of Secure Information Flow*, CACM 1976.
- Goguen & Meseguer, *Security Policies and Security Models*, IEEE S&P 1982.
- Landauer & Redmond, *A Lattice of Information*, CSFW 1993.
- Wittbold & Johnson, *Information Flow in Nondeterministic Systems*, 1990 (nondeducibility on strategies).
- Myers & Liskov, *A Decentralized Model for Information Flow Control*, SOSP 1997.
- Aumann, *Agreeing to Disagree*, Ann. Statist. 1976; Fagin, Halpern, Moses, Vardi, *Reasoning About Knowledge*, 1995.
- G. Smith, *On the Foundations of Quantitative Information Flow*, FoSSaCS 2009; Alvim et al., *The Science of Quantitative Information Flow*, Springer 2020.
- Dwork, *Differential Privacy*, ICALP 2006; Shokri et al., *Membership Inference Attacks*, IEEE S&P 2017; Sweeney, *k-anonymity*, 2002.
- Companions: `unviewable-state-root-cause.md`, `terminal-screen-ux-analysis.md`, `recipient-disclosure-matrix.html`.
