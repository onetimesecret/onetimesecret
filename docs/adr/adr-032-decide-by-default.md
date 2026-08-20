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

The recipient side deserves its own mention. The reveal page is the surface
most seen by people who never chose us, and it's the one our brand gets judged
on. Every variation we allow there splits that experience into versions we
can't all vouch for.

## Decision

We expose a choice only when whoever proposes it can show all four:

1. **Two identified users need opposite behaviour, and no single default works
   for both.** "Someone might prefer it" is not a user.
2. **The answer depends on facts we don't have.** Their compliance regime,
   their brand, their threat model, their recipients. If we could work out the
   better answer ourselves, then offering the choice is just refusing to do the
   work.
3. **The wrong default actually blocks them.** They can't reach an acceptable
   outcome with what already exists, at a cost they'd accept.
4. **Someone owns the cost for the life of the option.** The support answer,
   the test case, the doc paragraph, the a11y check, and all of it twice
   because there are two branches now.

Anything the recipient sees has to clear a higher bar: all four, plus a real
harm to the recipient under the default. A sender preferring something else is
not a harm. Operator branding is settled in
[ADR-026](adr-026-brand-nil-means-unconfigured.md) and later, and this record
does not reopen it.

When a proposal doesn't clear the bar, we pick what's best for the median
recipient and move on. That pick can be reopened later with evidence, such as
support volume, a lost deal, or a named regulation. Wanting it is not evidence.

The part worth remembering is that "make it configurable" is not a compromise
between two positions. It pays for both positions forever, and it hands the
unresolved argument to everyone who installs the product.

## Related

- [ADR-026](adr-026-brand-nil-means-unconfigured.md), absence as a load bearing signal
- [ADR-027](adr-027-one-authority-per-value.md), one authority per value
