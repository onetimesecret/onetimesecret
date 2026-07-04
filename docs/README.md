# Onetime Secret — Documentation

Reference documentation for developing, operating, and understanding Onetime
Secret. Each section has its own index; start there for a fuller listing.

Naming and structure conventions for this tree are recorded in
[`.gitignore`](./.gitignore).

## Sections

| Section | What's inside |
| --- | --- |
| [architecture/](./architecture/README.md) | System design, the layered frontend/backend model, and [decision records (ADRs)](./architecture/decision-records/README.md). |
| [authentication/](./authentication/README.md) | Auth modes (simple vs full), per-install and per-domain SSO, WebAuthn, OmniAuth testing. |
| [authorizations/](./authorizations/membership-entitlements.md) | Organization membership entitlements and role-intersected capabilities. |
| [api/](./api/README.md) | Pointer to the authoritative published API reference. |
| [product/](./product/README.md) | Product- and feature-level behaviour: secret lifecycle, invites, branding, email validation. |
| [development/](./development/README.md) | Local setup, i18n workflows, testing, isolated environments, accessibility. |
| [runbooks/](./runbooks/README.md) | Operational procedures for diagnosing and resolving specific production conditions. |
| [specs/](./specs/README.md) | Durable specifications and information-flow models for discrete features. |
| [test-plans/](./test-plans/README.md) | Intent-based, LLM-optimized test specifications and QA plans. |
| [branding-screenshots/](./branding-screenshots/README.md) | Visual verification captures for the branding system. |
| [diagrams/](./diagrams/) | Standalone SVG diagrams referenced by other docs. |

## Conventions

- **Filenames:** lowercase with hyphens (`custom-mail-sender.md`). ADRs are
  numbered (`adr-012-...`).
- **Every directory has an index** (`README.md`) so it can be navigated without
  a doc-site build step.
- **Point to the source of truth; don't restate it.** When behaviour is defined
  in code, config, or an ADR, link there rather than duplicating detail that
  will drift.
- **Prefer durable references.** Cite symbols, methods, and config keys rather
  than file line numbers or branch names, which go stale quickly.
