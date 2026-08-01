---
id: '032'
status: accepted
title: 'ADR-032: Decide by Default'
---

## Status

Accepted

## Date

2026-08-01

## Context

"Should we make it configurable?" is a reasonable question on its face. But
turn it over and you realize it's often punting a problem down the road
masquerading as flexibility. That has consequences.

Every mechanic multiplies support, QA, docs, design, and a11y surface for
its lifetime. It's also easier to add then it is to remove. Adding an option
later is a feature release; removing one is a breaking and/or disruptive
change.

## Decision

We expose a choice only when whoever proposes it can show all four:

1. **The split is real.** Two identified users need opposite behaviour and no
   single default works for both. "Someone might prefer" is not a user.
2. **The deciding facts are theirs, not ours.** The answer depends on their
   compliance regime, their brand, their threat model, or their recipients.
   If we could work out the better answer ourselves, offering the choice is
   just refusing to do the work.
3. **The wrong default is a blocker.** They cannot reach an acceptable outcome
   with what already exists, at tolerable cost.
4. **Someone owns the cost.** Support answer, test case, doc paragraph, and
   a11y check, for both branches, for its lifetime.

Anything the recipient sees needs more: all four, plus real harm to the
recipient under the default. A sender preferring something else is not harm.
Operator branding is settled in [ADR-026](adr-026-brand-nil-means-unconfigured.md)
and later, and this record does not reopen it.

When the test fails, we pick what is best for the median recipient. That pick
can be reopened with evidence: support volume, a lost deal, a named
regulation. Wanting it is not evidence.

The part worth remembering: "make it configurable" is not a compromise between
two positions. It pays for both positions forever, and hands the unresolved
argument to everyone who installs the product.

## Related

- [ADR-026](adr-026-brand-nil-means-unconfigured.md), absence as a load bearing signal
- [ADR-027](adr-027-one-authority-per-value.md), one authority per value
