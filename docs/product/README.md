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

## Document Types

- **Technical Design** (`type: technical-design`) — How systems work
- **Reference** (`type: reference`) — Lookup tables and specifications

## Contributing

When adding new documentation:
1. Add front matter with `title`, `type`, `status`, `updated`
2. Link from this index
3. Cross-reference related documents in a "Related Documents" section
