# Specifications

Durable specifications and models for discrete features — the intended
behaviour and its rationale, kept current with the code. Single-issue names are
avoided here; specs are titled by the behaviour they describe, not the ticket
that prompted them.

## Secret creation & permissions

- [secret-creation-flows.md](./secret-creation-flows.md) — The paths through
  which a secret can be created and the state each produces.
- [domain-permissions.md](./domain-permissions.md) — Permission rules governing
  secret creation on custom domains.

## Schema authority & the "no longer available" surface

How schema definitions relate, what goes wrong when a record's `state` falls
out of the canonical enum, and the disclosure policy for the terminal screens.

- [schema-source-of-truth.md](./schema-source-of-truth.md) — Treating the schema
  as the single source of truth, with validation at the boundary (design for
  #3496/#3514).
- [schema-problem-space.md](./schema-problem-space.md) — The territory: which
  schema-like definitions exist and what each is authoritative for.
- [unviewable-state-root-cause.md](./unviewable-state-root-cause.md) — The
  mechanism by which an out-of-enum / un-viewable `state` renders as the terminal
  "no longer available" screen.
- [recipient-disclosure-matrix.html](./recipient-disclosure-matrix.html) — The
  design source of truth (in prose) for what each observer may distinguish.
- [recipient-disclosure-flow-model.md](./recipient-disclosure-flow-model.md) —
  The same policy as a machine-checkable quantitative-information-flow model.
- [terminal-screen-ux-analysis.md](./terminal-screen-ux-analysis.md) — UX
  analysis of the terminal-screen failure surface, with referenceable
  opportunity IDs for follow-up work.
