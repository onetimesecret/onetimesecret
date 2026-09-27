# docs/adr/README.md

---

## Architecture Decision Records (ADRs)

An ADR records an architectural decision, the context that led to it, and its
consequences. Use this guide when creating or updating records in this
directory.

## Create an ADR

1. Confirm that the decision warrants a record. See [When to Write an ADR](#when-to-write-an-adr).
2. Copy [`adr-000.md`](adr-000.md), the directory template.
3. Assign the next sequential identifier and name the file `adr-NNN-kebab-slug.md`.
4. Complete the required `Status`, `Date`, `Context`, and `Decision` sections.
5. Keep the `status` value in the frontmatter and the `Status` section aligned.

### Status lifecycle

- **Proposed:** under discussion.
- **Accepted:** ratified by the team. Implementation may follow; record rollout in Implementation Notes.
- **Deprecated:** no longer relevant, but retained as history.
- **Superseded:** replaced by a newer ADR. Link to the replacement record.

## Write a useful record

Keep ADRs concise enough to read in a few minutes. Explain why the decision
was made, not only what was chosen.

- **Context** states the problem, constraints, and factors that require a decision.
- **Decision** states the choice and its core rationale. Keep the rationale here rather than repeating it in another section.
- Use optional sections only when they add information that does not fit in Context or Decision.
- Number records sequentially so that code, issues, and pull requests can refer to a stable identifier such as `ADR-001`.

### Trade-offs

Use `Trade-offs` for the inherent exchange: what the project gives up to obtain
a benefit, and the risks that make the choice conditional. Name concrete costs,
lost flexibility, and situational risks that a future reader needs to decide
whether the ADR should be superseded.

Do not use this section to restate the decision, list routine implementation
work, or separate generic positives and negatives.

### Related

Use `Related` to link ADRs and other durable documents that help readers
understand the decision. Omit it when there are no useful links. Do not use it
for transient implementation discussions or change-tracking metadata.

### Implementation Notes

`Implementation Notes` is a mutable addendum for details that do not change
the decision. Use it for:

- clarifications or edge cases found during implementation;
- rollout timing; and
- migration guidance.

Give every note a date and title.

## Keep decisions focused

Write one decision per ADR. Split choices that can be evaluated, approved, or
superseded independently. Keep choices together only when they stand or fall
together and share a lifecycle.

Separate ADRs make ownership and review clearer, let each decision change
without replacing an unrelated one, and give implementation work a precise
record to reference. Link related ADRs through `Related` rather than combining
them into one record.

Do not over-split. A one-sentence choice with no meaningful trade-off usually
belongs in a code comment at the call site, not an ADR.

## Preserve accepted decisions

After acceptance, do not rewrite the decision or its rationale. Record
clarifications and execution details in dated Implementation Notes. When the
decision itself changes, create a new ADR, mark the earlier one as
Superseded, and cross-link the records.

## When to Write an ADR

Write an ADR for a decision that:

- is expensive to reverse or constrains future options;
- affects multiple teams or components;
- establishes a pattern for later work; or
- resolves a technical debate.

Do not write an ADR for a decision that is:

- trivial or easy to reverse;
- an implementation detail within one component; or
- non-contentious standard practice.
