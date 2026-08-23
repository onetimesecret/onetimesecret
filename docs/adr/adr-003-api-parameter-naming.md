---
id: 003
status: accepted
title: ADR-003: API Parameter Naming Convention (u/p)
---

## Status
Accepted

## Date
2025-10-10

## Context

During PR #1798 review, automated tooling (Copilot) flagged the use of cryptic parameter names `u` (email/username) and `p` (password) in the authentication API endpoints. The suggestion was to use more descriptive names like `email` and `password` for improved code readability.

Key considerations:
- The `u`/`p` convention is used consistently across all authentication endpoints
- Backend Logic classes in `apps/api/v2/logic/` expect these parameter names
- Frontend composables (`src/composables/useAuth.ts`) send these parameters
- Integration tests rely on this convention
- The API is already in production with existing clients

The decision point: Should we refactor to use descriptive parameter names or maintain the existing convention?

## Decision

**We will maintain the existing `u`/`p` parameter naming convention** for authentication endpoints.

The convention:
- `u` = username/email field (user identifier)
- `p` = password field
- `shrimp` = CSRF token (existing convention)

This applies to:
- `/auth/login` - Sign in endpoint
- `/auth/create-account` - Registration endpoint
- `/auth/reset-password-request` - Password reset initiation

## Consequences

### Positive

- **Backwards Compatibility**: No breaking changes for existing API clients
- **Payload Efficiency**: Shorter parameter names reduce request payload size (matters at scale)
- **Consistency**: Uniform convention across all authentication endpoints
- **No Migration Risk**: Avoids potential bugs from incomplete refactoring across 50+ usage sites

### Negative

- **Reduced Readability**: New developers need to learn the convention
- **Documentation Need**: Requires explicit documentation of parameter meanings
- **API Discoverability**: Less self-documenting than descriptive names

### Neutral

- **Industry Precedent**: Many APIs use abbreviated parameter names (e.g., OAuth uses `client_id`, JWT uses `sub`)
- **Internal Convention**: Parameter names are implementation details when using typed clients/SDKs
- **Localized Impact**: Only affects authentication endpoints, not entire API surface

## Implementation Notes

### Future Considerations (2025-10-10)
If a v3 API is created with breaking changes, consider:
1. Providing both abbreviated and full parameter names during transition
2. Using JSON:API or similar standard that defines parameter naming
3. Using typed SDK generators to abstract parameter names from consumers (e.g. zod)
