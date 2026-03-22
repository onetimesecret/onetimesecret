// src/schemas/api/v2/responses/registry.ts
//
// Assembles individual response schemas into the responseSchemas lookup
// object. Consumers use this as a typed registry for Zod parsing.

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

// Single source of truth for response schemas
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

// Mapped type for all response shapes
export type ResponseTypes = {
  [K in keyof typeof responseSchemas]: z.infer<(typeof responseSchemas)[K]>;
};
