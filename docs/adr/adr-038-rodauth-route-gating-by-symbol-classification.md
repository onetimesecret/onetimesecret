---
id: 038
status: accepted
decided: 2026-08-13
title: "ADR-038: Rodauth Route Gating via Exhaustive Symbol Classification"
---

## Context

Full-mode authentication routes are served by Rodauth inside the Roda auth
app. Request-time policy gates apply to them — `restrict_to`
([ADR-034](adr-034-restrict-to-enforcement.md#restrict-to-is-an-access-control-not-a-display-preference))
first, the signin/signup opt-in axis (#4163) second — and each new axis has
to answer the same three questions: where does the gate hook in, what is a
route keyed by, and what happens to a route nobody classified. The first
gate answered them in file-local comments (`apps/web/auth/restrict_to.rb`);
with a second gate reusing the answers verbatim, they are shared mechanism,
recorded once here.

The recurring counter-proposal this ADR exists to answer: the rest of the
app declares per-route properties in Otto's `routes.txt`, so why not there?

Section headings declare their own citation anchors
(ADR-036#anchors-are-declared) — cite `ADR-038#slug`, not positions. <!-- adr-lint:ignore -->

## Decision

### Gate at before_rodauth, not in the routing table {#gate-at-before-rodauth}

Rodauth routes never pass through Otto: Rodauth builds `route_hash` once,
freezes it in `post_configure`, and dispatches internally. There is no
`routes.txt` row to carry a property, and routes cannot be un-mounted per
request or per host. Per-route policy therefore hooks `before_rodauth` — the
one chokepoint that fires inside the matched route, after `@current_route`
is set and CSRF is checked, before anything executes — and *emulates*
non-existence with the reject shape of
ADR-034#reject-as-not-found-not-forbidden.

Otto-dispatched auth surfaces (simple mode's Core controllers) gate in the
controller instead, through the same model-owned resolvers
(ADR-034#resolution-is-model-owned), so both modes share resolution rather
than each mode carrying its own annotation system.

Gates on the same routes compose in a fixed order, broadest-precedence
first, so a rejected request cannot distinguish which gate fired.

### Classify by route symbol, not URL {#classify-by-symbol-not-url}

Classification keys are the symbols Rodauth's `route(...)` declares (what
`@current_route` reports), never URL paths. Two reasons, both live:

- URLs are operator-configurable and several are renamed in
  `config/features/`; a path-keyed table silently stops matching.
- Loaded features can change what a route *means* without renaming it —
  `webauthn_verify_account` turns the `create_account`/`verify_account`
  ceremony into a WebAuthn one. A gate whose axis is sensitive to that
  re-meaning reclassifies by feature presence (see
  `Auth::RestrictTo::WEBAUTHN_VERIFY_ACCOUNT_ROUTES`); one whose axis is
  not (function-keyed axes like signin/signup) states that it is not.

### Classify exhaustively, or fail the build {#classify-exhaustively-or-fail}

Every Rodauth route appears in exactly one bucket per gate axis: gated, or
exempt with a stated reason (account-scoped, install-wide posture, not a
sign-in method, second-factor ceremony). A coverage spec enumerates the
mounted routes and fails when a route appears in no bucket — a new feature
route is a red test, never a silent default-open. Default-open is how a
gate rots while looking closed, which is worse than no gate: it invites
documenting an access control the server does not provide.

## Consequences

- Adding a Rodauth feature forces a classification decision per gate axis,
  at spec-failure time rather than in an audit.
- Gate modules stay thin: symbol tables plus input-gathering, with
  resolution owned by the models (ADR-034#resolution-is-model-owned).
- The cost is one Ruby constant per axis instead of declarative routing
  metadata — accepted, because the metadata cannot live where these routes
  are dispatched.
