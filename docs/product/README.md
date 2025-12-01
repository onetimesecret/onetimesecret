---
title: Product Documentation
type: index
updated: 2025-11-30
---

# Product Documentation

Frontend architecture and design documentation for Onetime Secret.

## Architecture

| Document | Purpose | Status |
|----------|---------|--------|
| [Interaction Modes](interaction-modes.md) | Core frontend architecture: organizing code by user intent | Draft |

## Reference

| Document | Purpose |
|----------|---------|
| [Request Lifecycle](request-lifecycle.md) | How requests flow through the system (routing → rendering) |
| [Secret Lifecycle](secret-lifecycle.md) | FSM states for secret entities (idle → revealed → burned) |
| [URI Path Mapping](uri-paths-to-views-structure.md) | URL → Vue component mapping table |

## Key Concepts

### Interaction Modes

The frontend is organized into four apps based on what users are doing:

| App | Mode | Routes | Purpose |
|-----|------|--------|---------|
| **Secret** | Conceal/Reveal | `/`, `/secret/:key`, `/receipt/:key` | Transactional: create & view secrets |
| **Workspace** | Manage | `/dashboard/*`, `/account/*` | Account management |
| **Kernel** | Admin | `/colonel/*` | System administration |
| **Session** | Gateway | `/signin`, `/signup`, `/logout` | Authentication |

### Three Dimensions

| Dimension | Binding Time | Controls |
|-----------|--------------|----------|
| Interaction Mode | Design-time | Which app handles the request |
| Domain Context | Runtime | How it looks (canonical vs branded) |
| Homepage Mode | Deployment-time | Whether secret creation is permitted |

## Tasks

| Document | Purpose | Status |
|----------|---------|--------|
| [Vue Frontend Discovery](tasks/vue-frontend-discovery.md) | Map current architecture before migration | Complete |
| [Migration Manifest](tasks/interaction-modes-migration-manifest.md) | File-by-file migration plan for big bang restructure | Pending |
| [Architecture Gap Analysis](tasks/architecture-gap-analysis.md) | Compare current vs target, size gaps | Pending |

## Document Types

- **Technical Design** (`type: technical-design`) — How systems work
- **Reference** (`type: reference`) — Lookup tables and specifications
- **Assessment** (`type: assessment`) — Current state snapshots before change

## Running

1. "Run docs/product/tasks/vue-frontend-discovery.md"
2. (The agent produces the assessment)
3. "Run docs/product/tasks/architecture-gap-analysis.md"
4. (The agent produces the gap inventory)


### The workflow:

```plain
tasks/vue-frontend-discovery.md
    ↓ produces
assessments/vue-frontend-current-state.md
    ↓ consumed by
tasks/architecture-gap-analysis.md
    ↓ produces
assessments/vue-frontend-gap-analysis.md
```

## Contributing

When adding new documentation:
1. Add front matter with `title`, `type`, `status`, `updated`
2. Link from this index
3. Cross-reference related documents in a "Related Documents" section
