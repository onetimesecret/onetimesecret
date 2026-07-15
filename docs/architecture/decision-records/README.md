## Architecture Decision Records (ADRs)

Documents that capture important architectural decisions along with their context and consequences. They're a best practice for technical documentation in open-source projects.

**Lifecycle:**
- Proposed: Under discussion
- Accepted: Decision ratified by the team (implementation may follow; track rollout in Implementation Notes)
- Deprecated: No longer relevant but kept for history
- Superseded: Replaced by a newer ADR (reference the new one)

### Keys to Success

- **Be courteous**: ADRs should be readable in 2-3 minutes, so focus on why. The decision itself is less important than the reasoning.
- **Avoid formulaic sections**: Don't force content into rigid templates. If your core argument is complete in Context and Decision, stop there. Skip sections that merely reorganize the same points.
- **Combine related content**: Merge rationale directly into the Decision section. Trade-offs are optional—only include them when they add genuine insight.
- **Immutable**: Once accepted, don't edit the decision; that's like re-writing history. Use Implementation Notes or create another ADR to supersede.
- **Numbered sequentially**: Makes referencing easy (`ADR-001`, `ADR-002`, etc.)
- **One decision per ADR**: Don't bundle multiple choices together

### Splitting vs. Combining Decisions

This expands the "One decision per ADR" key above: when two choices show up together, default to **separate ADRs — one decision per record**. Four reasons:

1. **One decision per record (atomicity).** The founding convention — Nygard's original format, `adr-tools`, MADR, the adr.github.io community, and AWS/Google/Microsoft's ADR guidance — is one architecturally-significant decision per file. The unit is "things that stand or fall together." Two choices that can be evaluated independently don't.
2. **Different owners and review triggers.** A naming/structure decision and, say, a privacy/legal decision have different reviewers. Bundling forces a lawyer to wade through structural debates, and an engineer to wade through legal nuance.
3. **Different lifecycles + immutability.** Quality ADR sets treat accepted records as immutable and **supersede rather than edit**. The volatile decision is usually the one most likely to change; if it's welded to a stable decision, revising one paragraph means superseding the whole record. Split, and you supersede just the part that moved.
4. **Precise traceability.** A 1:1 decision↔ADR mapping keeps `git blame` and PR references clean: code that implements a decision links to *that* ADR, not to a grab-bag.

**What mature ADR sets do:** sequentially numbered, immutable, short, single-topic records with a consistent template and a *liberal* "Related / References" section that cross-links siblings (Kubernetes KEPs, Arachne, AWS Prescriptive Guidance all do this). Cross-linking is how you get the "these belong together" benefit without a monolith. Keep the status lifecycle explicit (Proposed → Accepted → Superseded) and date every amendment.

**Don't over-split, either.** If a decision is a single sentence with no trade-offs, a code comment at the call site suffices — it doesn't need a record. A choice earns its own ADR when it has real trade-offs, a regulatory or cross-cutting dimension, or a test/contract obligation attached to it.

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
