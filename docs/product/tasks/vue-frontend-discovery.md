---
title: Vue Frontend Architecture Discovery
type: assessment
status: pending
created: 2025-11-30
feeds-into: interaction-modes.md
agent: Explore
---

# Vue Frontend Architecture Discovery

Agent prompt for mapping the current Vue 3 frontend before migrating to the Interaction Modes architecture.

## Objective

Map the current Vue 3 frontend architecture to understand component organization, state flow, and how pieces interconnect before planning any refactoring.

## Discovery Tasks

### 1. Directory Structure
- List `src/` top-level directories and their purposes
- Identify which folders contain components vs views vs utilities
- Note any existing `apps/` structure if present (proposed architecture may be partially implemented)

### 2. Component Organization
- Count components in `src/components/` — are they flat or categorized?
- Identify container components (ones that orchestrate others)
- Find "branded" vs "canonical" variants — where do they live?
- Look for `*Container.vue` patterns that switch between variants

### 3. State Management
- List all Pinia stores in `src/stores/`
- Identify which stores handle: auth, branding/domain, secrets, UI state
- Find where `window.__ONETIME_STATE__` is consumed
- Trace how `domain_strategy` flows from window state to components

### 4. Routing
- Read `src/router/` configuration
- Map routes to their components
- Identify route guards and their logic
- Note any route-level branching based on domain/auth state

### 5. Key Composables
- Search for `use*.ts` files in `src/composables/` or similar
- Document what each major composable provides
- Find where branding/theming logic currently lives

## Output Format

Produce a structured report:

```
## Current Architecture Summary

### Directory Map
src/
├── [folder]: [purpose]
...

### Component Categories
- [category]: [count] components, [example files]

### State Flow
[diagram or description of how state moves through the app]

### Pain Points Observed
- [specific duplication or unclear boundaries found]

### Alignment with Interaction Modes Doc
- [what matches the proposed architecture]
- [what differs from the proposed architecture]
```

## Constraints

- Read-only exploration — no code changes
- Focus on structure, not implementation details
- Note file paths for key findings
- Flag any `canonical/` and `branded/` folder patterns specifically

## Usage

Invoke via Task tool:

```
subagent_type: Explore
prompt: [copy Discovery Tasks and Output Format sections above]
description: Vue frontend architecture discovery
```
