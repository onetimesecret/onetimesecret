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

## Required Context

**Read first**: `docs/product/interaction-modes.md`

The target architecture organizes by **interaction mode** (what the user is doing), NOT by domain (canonical vs branded). This is the core insight:

| App | Mode | Routes | Purpose |
|-----|------|--------|---------|
| `secret/` | Conceal/Reveal | `/`, `/secret/:key`, `/receipt/:key` | Transactional |
| `workspace/` | Manage | `/dashboard/*`, `/account/*` | Account management |
| `session/` | Gateway | `/signin`, `/signup`, `/logout` | Authentication |
| `kernel/` | Admin | `/colonel/*` | System administration |

**Target structure**:
```
src/apps/
├── secret/
│   ├── conceal/          # Homepage, IncomingForm
│   └── reveal/           # ShowSecret, ShowReceipt
├── workspace/
│   ├── dashboard/
│   ├── account/
│   └── billing/
├── session/
│   └── views/            # Login, Register, Logout
└── kernel/
    └── views/            # Colonel admin views
```

Domain context (canonical vs branded) is handled by **composables** within components, NOT by folder structure. The `branded/` and `canonical/` folders are the **problem being solved**, not a pattern to replicate.

---

## Objective

Map the **current** Vue 3 frontend architecture to understand:
1. What exists today
2. How it differs from the target structure
3. What migration steps are needed

## Discovery Tasks

### 1. Directory Structure
- List `src/` top-level directories and their purposes
- Identify which folders contain components vs views vs utilities
- Note any existing `apps/` structure (target may be partially implemented)

### 2. Component Organization
- Count components in `src/components/` — flat or categorized?
- Identify container components (orchestrators)
- **Find `branded/` vs `canonical/` variants** — these are migration targets
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

```markdown
## Current Architecture Summary

### Directory Map
src/
├── [folder]: [purpose]
...

### Component Categories
- [category]: [count] components, [example files]

### State Flow
[diagram or description of how state moves through the app]

### Domain-Based Patterns Found (Migration Targets)
- [list files/folders organized by canonical/branded]
- [container components that switch variants]

### Gap Analysis vs Target Architecture

| Target App | Current Location | Migration Notes |
|------------|------------------|-----------------|
| `secret/conceal/` | [where Homepage lives now] | [what needs to move] |
| `secret/reveal/` | [where ShowSecret lives now] | [what needs to move] |
| `workspace/` | [current dashboard location] | [what needs to move] |
| `session/` | [current auth views] | [what needs to move] |
| `kernel/` | [current colonel views] | [what needs to move] |
```

## Output Location

Save results to: `docs/product/assessments/vue-frontend-current-state.md`

## Constraints

- Read-only exploration — no code changes
- Focus on structure, not implementation details
- Note file paths for key findings
- **Flag `canonical/` and `branded/` folder patterns as migration targets**
- Any proposed structure must follow the interaction modes pattern above

## Usage

Invoke via Task tool:

```
subagent_type: Explore
prompt: [copy entire document from "Required Context" through "Constraints"]
description: Vue frontend architecture discovery
```
