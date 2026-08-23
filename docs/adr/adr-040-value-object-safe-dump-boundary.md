---
id: "040"
status: accepted
title: "ADR-040: Value Objects Share the Model safe_dump Boundary"
---

## Status

Accepted

## Date

2026-08-16

## Context

Our Familia::Horreum models follow a serialization boundary convention.
`#safe_dump` is a positive allow-list, the only shape that may cross an
API/HTTP boundary, while `#to_h` is the full internal representation, free to
carry tokens, join keys, and PII. `SessionMetadata`, for example, omits
`active_session_id_hmac` from its `safe_dump_fields` on purpose: it is an
internal join key, not something the colonel view renders. The convention is a
discipline callers follow, not a mechanism the type enforces: code serializes
`safe_dump` and never `to_h`.

Operation results are increasingly plain Ruby 3.2+ `Data` value objects
(`Data.define`). `Data` earns `#to_h` for free, and it is genuinely useful:
pattern matching, `#with`, in-memory joins, logging inside a trust boundary.

`Operations::Sessions::ListForCustomer` surfaced the tension. Its rows must
carry both a public projection (`SessionMetadata#safe_dump`) and an internal
correlation key (`active_session_id_hmac`) that the Rodauth active-sessions
join needs but that must never reach a response. A `Data` row exposes both
through `#to_h`; the moment anyone splats it into a response, the join key
leaks.

An earlier iteration hand-rolled a frozen object that deliberately did **not**
respond to `#to_h`, to make the leak structurally impossible. That solved the
one case but introduced a second, inconsistent shape: the next reader, seeing a
bespoke class beside a dozen `Data`-based results, either "fixes" it back to a
plain `Data` (silently reopening the hole) or cargo-cults the frozen class
where an ordinary `Data` would have been fine.

## Decision

Value objects that carry a mix of public projection and internal data get the
**same two-method contract the models already have**, not a bespoke shape:

- `#to_h`: full, internal, indiscriminate (`Data`'s default). Never crosses a
  boundary.
- `#safe_dump`: explicit positive allow-list. The only shape that may.

`Onetime::SafeDumpable` (`lib/onetime/safe_dumpable.rb`) provides this for
value objects, mirroring Familia's `safe_dump_fields` DSL. Include it, declare
the allow-list, and undeclared members are absent from `#safe_dump` while
remaining reachable via their readers and `#to_h`. A value object whose public
projection is a single already-safe member (e.g. a member that is itself a
model `safe_dump` row) overrides `#safe_dump` directly.

The convention is then uniform across the codebase, whether the object is a
Horreum model or a `Data` result row: **serialize `safe_dump`, never `to_h`.**
Crippling `#to_h` to mechanically enforce this was **rejected**. It trades a
real, consistent boundary for a one-off structural trick that the codebase
cannot generalize.

## Trade-offs

The protection is a **convention, not a structural guarantee**. `#to_h` on a
value object still exposes its internal members, exactly as a model's does, so
HTTP-facing code that reaches for `#to_h` (or blindly splats the object) instead
of `#safe_dump` will leak, and the type cannot stop it. We accepted this to keep
one uniform boundary rule across models and value objects; the alternative (a
bespoke `#to_h`-less type) buys a structural guarantee for one case at the cost
of a second, inconsistent serialization shape the codebase cannot generalize.
The enforcement surface is therefore the boundary rule, its tests, and review.
`#safe_dump` is at least fail-closed (an undeclared allow-list dumps `{}`, never
the internal members).

## Related

- [ADR-022](adr-022-secret-activity-network-capture-privacy.md): network-context capture privacy (the `safe_dump` allow-list as a privacy boundary)
- [ADR-027](adr-027-one-authority-per-value.md): one authority per value
