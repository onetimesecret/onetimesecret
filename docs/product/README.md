---
title: Product Documentation
type: index
updated: 2026-02-08
---

# Product Documentation

Frontend architecture and design documentation for Onetime Secret.

## Interaction Modes

The frontend is organized into four apps based on what users are doing:

| App | Mode | Routes | Purpose |
|-----|------|--------|---------|
| **Secret** | Conceal/Reveal | `/`, `/secret/:key`, `/receipt/:key` | Transactional: create & view secrets |
| **Workspace** | Manage | `/dashboard/*`, `/account/*` | Account management |
| **Kernel** | Admin | `/colonel/*` | System administration |
| **Session** | Gateway | `/signin`, `/signup`, `/logout` | Authentication |

| Dimension | Binding Time | Controls |
|-----------|--------------|----------|
| Interaction Mode | Design-time | Which app handles the request |
| Domain Context | Runtime | How it looks (canonical vs branded) |
| Homepage Mode | Deployment-time | Whether secret creation is permitted |


## Brand Customization System

Each installation or custom domain can express a full visual identity through configuration — a single hex color generates an 11-shade oklch palette at runtime, while product name, typography, and corner style flow through i18n and CSS variables. The system is designed so that Onetime Secret's own look is just one possible configuration.

See [brand/](brand/) for the full product bible (context, architecture, cross-cutting concerns, implementation, and decision log).
