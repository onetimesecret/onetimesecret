---
id: "045"
status: proposed
title: "ADR-045: Prioritizing Work"
---

## Status

Proposed

## Date

2026-09-17

## Context

Release planning must account for both the expected value of a change and the
uncertainty and structural tension surrounding it. Implementation effort alone
does not capture whether work resolves an important defect, strengthens a
foundation, or introduces complexity that will persist after delivery.

Evidence is often incomplete when priorities are first considered. The
planning model therefore needs to identify the uncertainties that could change
release placement, guide investigation toward those uncertainties, and allow
priorities to change as evidence improves.

## Decision

Adopt the following decision model for planning and release placement.

## Decision model

Prioritize items by their expected contribution to security, privacy, UX,
functionality, and clarity—and by how much ongoing complexity they remove.

Use a Bayesian approach to uncertainty: begin with evidence-backed
expectations, investigate the uncertainties that could change release
placement, and update priorities after each verification step. Do not assign
numerical probabilities without supporting data.

“Tension” means conflicting authorities, coupled behavior, hidden exceptions,
and difficult recovery—not simply implementation effort.

| Impact and tension | Treatment |
|---|---|
| High impact, high tension | Investigate first and resolve the underlying design in the current release. |
| High impact, low tension | Implement early; these strengthen the foundation. |
| Low impact, low tension | Include alongside related work when they introduce no independent dependency. |
| Low impact, high tension | Defer until evidence establishes a worthwhile benefit. |

Current evidence strongly supports inconsistent authentication decisions as a
defect. It does **not** establish which strict-session check rejected the
captured request: the HTTP captures omit the bootstrap body and subsequent API
refusal reason. Resolving that uncertainty is the first investigation step,
without making the broader consistency fix dependent on reproducing the
original incident.

## Trade-offs

- **We lose:** A fixed priority order based only on apparent urgency or
  implementation effort. Some work must pause while evidence that could change
  its release placement is gathered.
- **We gain:** Priorities that respond to evidence, distinguish structural
  tension from raw effort, and favor work that improves the product while
  removing ongoing complexity.
- **Risk:** Qualitative Bayesian reasoning can become intuition presented as
  evidence. Priority decisions must name their evidence, uncertainties, and
  the verification step that would cause the decision to change.

## Consequences

Planning and release decisions state both expected impact and tension. When a
material uncertainty could move an item between treatments, the next step is
an investigation that resolves that uncertainty rather than an unsupported
numerical estimate.

High-impact consistency defects remain eligible for the current release even
when the initiating incident cannot be reproduced completely. Investigation
should identify the immediate failure mechanism, but the broader correction is
judged on the evidence for inconsistent behavior and its expected impact.
