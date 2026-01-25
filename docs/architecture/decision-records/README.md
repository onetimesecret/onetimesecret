## Architecture Decision Records (ADRs)

Documents that capture important architectural decisions along with their context and consequences. They're a best practice for technical documentation in open-source projects.

**Lifecycle:**
- Proposed: Under discussion
- Accepted: Decision approved and implemented
- Deprecated: No longer relevant but kept for history
- Superseded: Replaced by a newer ADR (reference the new one)

### Keys to Success

- **Be courteous**: ADRs should be readable in 2-3 minutes, so focus on why. The decision itself is less important than the reasoning.
- **Avoid formulaic sections**: Don't force content into rigid templates. If your core argument is complete in Context and Decision, stop there. Skip sections that merely reorganize the same points.
- **Combine related content**: Merge rationale directly into the Decision section. Trade-offs are optional—only include them when they add genuine insight.
- **Immutable**: Once accepted, don't edit the decision; that's like re-writing history. Use Implementation Notes or create another ADR to supersede.
- **Numbered sequentially**: Makes referencing easy (`ADR-001`, `ADR-002`, etc.)
- **One decision per ADR**: Don't bundle multiple choices together

### Implementation Notes Section

Optional addenda for clarifications and execution details. Use it for:

- **Clarifications**: Technical details or edge cases discovered during implementation
- **Rollout timelines**: When the decision will be implemented relative to when it was accepted
- **Migration notes**: How to transition from the old state to the new one

This section is mutable. Each note should be dated and titled.

### When to Write ADRs

Write ADRs for decisions that:
- Are expensive to reverse or constrain future options
- Affect multiple teams or components
- Establish patterns for others
- Resolve technical debates

Don't write ADRs for:
- Trivial or easily reversible
- Implementation details within a single component
- Non-contentious or standard practice decisions
