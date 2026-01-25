---
id: 001
status: accepted
title: ADR-001: Naming and Separation of Rack Applications
---

## Status
Accepted

## Date
2025-10-08

## Context

One Time Secret is a monolith codebase using multiple Rack applications mounted via a registry pattern at different paths. The existing structure includes API apps (`apps/api/v1`, `apps/api/v2`), authentication (`auth`), and email validation (`truemail`).

The challenge was determining:
1. How to name the main frontend application directory without creating logical inconsistencies?
2. Whether to separate anonymous/public functionality from authenticated user functionality?
3. What naming convention to use that scales as new applications are added?

Key constraints:
- All applications are Rack-based web apps, so naming one "web" implies it's the only web component
- Core functionality (secret creation/retrieval) is available to both anonymous (non-authenticated) and authenticated users
- Anonymous traffic and authenticated traffic are similar but different in terms of user experience and security requirements
- Need to share Vue frontend components and backend code between apps

## Decision

**Naming Convention:**
- Use functional naming for all Rack applications, broadly split into api and web directories
- Name directories based on what the application does, not what it is; avoid generic terms like "web" or "frontend" that imply exclusivity

**Application Separation:**
- Separate anonymous/public functionality into a dedicated Rack app (`apps/public`)
- Separate authenticated user functionality into a dedicated Rack app (`apps/account`)
- Keep project-specific shared code in `lib/onetime/`
- Keep potentially extractable shared code in `lib/` (code that could become separate repositories but isn't yet)

**Directory Structure:**
```
apps/
├── public/        # Anonymous secret creation/retrieval
├── account/       # Authenticated user experience (dashboard, domains, settings)
├── auth/          # Authentication service
├── api/
│   └── v1/
│   └── v2/
lib/
├── onetime/       # Project-specific models, services, utilities
├── [other]/       # Shared code that could be extracted but isn't yet
│
src/               # Vue application
```

**URL Path Structure:**
- Other than `public` the paths typically match the directory structure
- No generic containers like `/app`
- Optional shorthand for high-volume resources (e.g. `/s/[key]` for secrets)

## Consequences

### Positive
- Clear mental model: Directory boundaries reinforce conceptual boundaries between anonymous and authenticated functionality
- Reduced blast radius: Changes to account management can't break core secret creation flow
- Independent optimization: Can tune performance/caching separately for each use case
- Logical consistency: All apps named by function, no implied hierarchy
- Scalability: Naming pattern works as additional apps are added

### Negative
- Additional coordination: Sharing code between apps requires more disciplined dependency management
- Organizational complexity: More directories and mount points to understand
- Potential duplication: Risk of reimplementing similar features if shared code isn't leveraged properly
- Deployment coordination: Changes to shared libraries affect multiple apps

### Neutral
- Requires explicit code sharing strategy with clear dependency rules (`lib/onetime/` may reference `lib/`, but not vice versa)
- Need to maintain clear boundaries about which functionality belongs in which app
- Router configuration becomes more explicit about mount paths and responsibilities

## Implementation Notes

### Rollout Timeline
This ADR is accepted for implementation targeting release 0.23. As of 2025-10-10, the `apps/` directory structure does not yet fully reflect this decision - restructuring work is in progress. This ADR documents the intended architecture to guide ongoing development.

### lib/ Dependency Rules
Code organization follows a strict dependency hierarchy:
- `lib/onetime/` contains project-specific code and may reference anything in `lib/`
- `lib/` contains potentially extractable code (e.g., `lib/chimera.rb` for mustache compatibility) and must not reference `lib/onetime/`

This ensures clean extraction paths if/when `lib/` code graduates to separate repositories.
