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
  loginResponseSchema,
  createAccountResponseSchema,
  logoutResponseSchema,
  resetPasswordRequestResponseSchema,
  resetPasswordResponseSchema,
} from './auth';
// Colonel schemas moved to internal registry (see @/schemas/api/internal/responses)
import { csrfResponseSchema } from './csrf';
import {
  brandSettingsResponseSchema,
  customDomainResponseSchema,
  customDomainListResponseSchema,
  imagePropsResponseSchema,
  jurisdictionResponseSchema,
} from './domains';
import { feedbackResponseSchema } from './feedback';
import {
  systemStatusResponseSchema,
  systemVersionResponseSchema,
  supportedLocalesResponseSchema,
} from './meta';
import {
  incomingConfigResponseSchema,
  incomingSecretResponseSchema,
  validateRecipientEnvelopeSchema,
} from './incoming';
// Organization schemas moved to internal registry (see @/schemas/api/internal/responses)
import { receiptResponseSchema, receiptListResponseSchema } from './receipts';
import {
  concealDataResponseSchema,
  secretResponseSchema,
  secretListResponseSchema,
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

  // Incoming
  incomingConfig: incomingConfigResponseSchema,
  incomingSecret: incomingSecretResponseSchema,
  validateRecipient: validateRecipientEnvelopeSchema,

  // Meta
  systemStatus: systemStatusResponseSchema,
  systemVersion: systemVersionResponseSchema,
  supportedLocales: supportedLocalesResponseSchema,

  // Feedback
  feedback: feedbackResponseSchema,

  // CSRF
  csrf: csrfResponseSchema,

  // Authentication (Rodauth-compatible)
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
