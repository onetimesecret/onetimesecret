// src/schemas/api/auth/index.ts
//
// Rodauth JSON API response schemas for authentication flows.
//
// ═══════════════════════════════════════════════════════════════════════════════
// SSO SCHEMA ORGANIZATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// SSO schemas are intentionally NOT in this directory. They live in:
//
// 1. Login page SSO buttons (what providers to show):
//    → src/schemas/contracts/bootstrap.ts → ssoConfigSchema, ssoProviderSchema
//    → Consumed by ConfigSerializer.build_sso_config / build_tenant_sso_response
//
// 2. Admin SSO configuration CRUD (managing per-org credentials):
//    → src/schemas/api/organizations/requests/sso-config.ts
//    → src/schemas/contracts/org-sso-config.ts
//    → Used by /api/v2/organizations/:extid/sso endpoints
//
// 3. SSO auth callbacks:
//    → No JSON schemas needed - OmniAuth uses HTTP redirects, not JSON API
//
// This directory contains only Rodauth JSON API responses (login, signup, MFA,
// password reset, etc.) which use a different response format than SSO flows.
// ═══════════════════════════════════════════════════════════════════════════════

export * from './responses';
