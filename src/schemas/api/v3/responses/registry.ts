// src/schemas/api/v3/responses/registry.ts
//
// Assembles individual response schemas into the responseSchemas lookup
// object. Consumers use this as a typed registry for Zod parsing.
//
// Separated from index.ts barrel to follow the same pattern as V2's registry.
// This allows the OpenAPI generator to import version-specific registries
// without pulling in barrel re-exports.

import { z } from 'zod';
import {
  accountResponseSchema,
  apiTokenResponseSchema,
  checkAuthResponseSchema,
  customerResponseSchema,
} from './account';
import {
  createAccountResponseSchema,
  loginResponseSchema,
  logoutResponseSchema,
  resetPasswordRequestResponseSchema,
  resetPasswordResponseSchema,
} from './auth';
// Colonel schemas moved to internal registry (see @/schemas/api/internal/responses)
// CSRF handled via dedicated endpoint, not in response registry
import {
  brandSettingsResponseSchema,
  customDomainListResponseSchema,
  customDomainResponseSchema,
  imagePropsResponseSchema,
  jurisdictionResponseSchema,
} from './domains';
import { feedbackResponseSchema } from './feedback';
import {
  supportedLocalesResponseSchema,
  systemStatusResponseSchema,
  systemVersionResponseSchema,
} from './meta';
// Organization schemas moved to internal registry (see @/schemas/api/internal/responses)
import { receiptListResponseSchema, receiptResponseSchema } from './receipts';
import {
  concealDataResponseSchema,
  secretListResponseSchema,
  secretResponseSchema,
} from './secrets';

// ─────────────────────────────────────────────────────────────────────────────
// Response schema registry
// ─────────────────────────────────────────────────────────────────────────────

/** Keyed lookup of all V3 response schemas. Used by the OpenAPI generator
 *  and Pinia stores for runtime Zod parsing. */
export const responseSchemas = {
  // Account
  account: accountResponseSchema,
  apiToken: apiTokenResponseSchema,
  checkAuth: checkAuthResponseSchema,
  customer: customerResponseSchema,

  // Secrets
  concealData: concealDataResponseSchema,
  secret: secretResponseSchema,
  secretList: secretListResponseSchema,

  // Domains / brand
  brandSettings: brandSettingsResponseSchema,
  customDomain: customDomainResponseSchema,
  customDomainList: customDomainListResponseSchema,
  imageProps: imagePropsResponseSchema,
  jurisdiction: jurisdictionResponseSchema,

  // Receipts
  receipt: receiptResponseSchema,
  receiptList: receiptListResponseSchema,

  // Meta
  systemStatus: systemStatusResponseSchema,
  systemVersion: systemVersionResponseSchema,
  supportedLocales: supportedLocalesResponseSchema,

  // Feedback
  feedback: feedbackResponseSchema,

  // Authentication (Rodauth-compatible)
  // NOTE: These auth schemas are not referenced by any API routes (auth routes
  // live in apps/web/core/routes.txt). They are included here because the Vue
  // frontend (useAuth.ts) imports them for runtime Zod parsing of auth responses.
  login: loginResponseSchema,
  createAccount: createAccountResponseSchema,
  logout: logoutResponseSchema,
  resetPasswordRequest: resetPasswordRequestResponseSchema,
  resetPassword: resetPasswordResponseSchema,
} as const;

// ─────────────────────────────────────────────────────────────────────────────
// Mapped types
// ─────────────────────────────────────────────────────────────────────────────

export type ResponseTypes = {
  [K in keyof typeof responseSchemas]: z.infer<(typeof responseSchemas)[K]>;
};
