// src/schemas/api/index.ts
//
// Directory structure mirrors apps/api/ routes:
//
// VERSIONED (public API - secrets, receipts):
//   v1/, v2/, v3/    Stable, backwards-compatible, published
//
// INTERNAL (non-versioned - frontend/admin):
//   account/         Account, billing, colonel (admin)
//   auth/            Login, signup, MFA, sessions
//   organizations/   Org CRUD, members
//   domains/         Custom domain management
//   invite/          Invitation flows
//
// Internal routes are high-churn and unpublished. They do not follow
// versioned API management. Vestigial v2 refs in internal schemas are
// tech debt from when all routes lived under v2.

export * as auth from './auth';
export * as v3 from './v3';
export * as account from './account';
