---
title: Architecture Gap Analysis
type: assessment
status: pending
created: 2025-12-01
inputs:
  - tasks/vue-frontend-discovery.md (current state)
  - interaction-modes.md (target state)
feeds-into: migration-plan
agent: Explore
---

# Architecture Gap Analysis

Compare current Vue frontend against the Interaction Modes target architecture.

## Inputs

- **Current State**: `docs/product/assessments/vue-frontend-current-state.md`
- **Target State**: `interaction-modes.md` sections: "The Solution", "Architecture"

## Output Location

Save results to: `docs/product/assessments/vue-frontend-gap-analysis.md`

## Output: Gap Inventory

```markdown
| Area | Current | Target | Gap Type | Effort | Dependencies |
|------|---------|--------|----------|--------|--------------|
| ... | ... | ... | Restructure/Refactor/New/Remove | S/M/L | ... |
```

## Agent Prompt

```
Compare these two inputs and produce a gap inventory table:

CURRENT STATE:
[paste assessment output]

TARGET STATE (from interaction-modes.md):
- Apps: secret/, workspace/, session/, kernel/
- Secret app: conceal/ + reveal/ subfolders
- Domain branching via useSecretContext() composable, not container components
- Layouts in shared/layouts/ named by purpose (TransactionalLayout, ManagementLayout)

For each gap, classify:
- Gap Type: Restructure | Refactor | New | Remove
- Effort: S (hours) | M (days) | L (weeks)
- Dependencies: what must happen first

Focus on structural gaps, not implementation details.
```

## Usage

```
subagent_type: Explore
prompt: [above]
description: Architecture gap analysis
```
