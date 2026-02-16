// src/schemas/api/auth/endpoints/auth.ts

import { z } from 'zod';

/**
 * Rodauth-compatible authentication response schemas
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 * AUTHENTICATION FLOW OVERVIEW
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * This module defines Zod schemas for validating Rodauth JSON API responses.
 * The authentication flow has multiple paths depending on account configuration:
 *
 * 1. STANDARD LOGIN (no MFA):
 *    POST /auth/login → { success: "You have been logged in" }
 *    → User is fully authenticated, redirect to dashboard
 *
 * 2. LOGIN WITH MFA ENABLED:
 *    POST /auth/login → { success: "...", mfa_required: true, mfa_methods: [...] }
 *    → User has partial auth (awaiting_mfa=true), redirect to /mfa-verify
 *    POST /auth/otp-auth → { success: "You have been multifactor authenticated" }
 *    → User is fully authenticated (awaiting_mfa=false), redirect to dashboard
 *
 * 3. ERROR RESPONSES:
 *    Any endpoint → { error: "message", "field-error": ["field", "message"] }
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 * ZOD UNION ORDERING (CRITICAL)
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * Zod unions match the FIRST schema that validates successfully. This means:
 * - More specific schemas MUST come before less specific ones
 * - { success, mfa_required } must precede { success } alone
 *
 * If order is wrong, Zod strips the MFA fields during validation, breaking
 * the login flow for MFA-enabled accounts.
 *
 * Rodauth JSON API response format:
 * - Success: { success: "message" }
 * - Error: { error: "message", "field-error": ["field", "error"] }
 */

// ─────────────────────────────────────────────────────────────────────────────
// Base Response Schemas
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Billing redirect information returned after login/signup when user
 * should be redirected to checkout (e.g., upgrading during signup flow).
 * Only present when billing is enabled and user needs to complete checkout.
 *
 * Terminology:
 * - product: Plan identifier (e.g., 'identity_plus_v1')
 * - interval: Billing frequency choice ('monthly' or 'yearly')
 */
const billingRedirectSchema = z.object({
  product: z.string(),
  interval: z.string(),
  valid: z.boolean(),
});

export type BillingRedirect = z.infer<typeof billingRedirectSchema>;

/**
 * Standard success response - used when no additional data is needed.
 * Example: logout, password change, account verification
 */
const authSuccessSchema = z.object({
  success: z.string(),
});

/**
 * Success response with optional billing redirect.
 * Returned by /auth/login or /auth/create-account when user should be
 * redirected to checkout after authentication.
 */
const authSuccessWithBillingSchema = z.object({
  success: z.string(),
  billing_redirect: billingRedirectSchema.optional(),
});

/**
 * Success response with MFA requirement flag.
 * Returned by /auth/login when the account has MFA enabled.
 *
 * The presence of mfa_required=true indicates the user has completed
 * password authentication but must still verify with OTP/recovery code.
 */
const authSuccessWithMfaSchema = z.object({
  success: z.string(),
  mfa_required: z.boolean(),
  mfa_auth_url: z.string().optional(),
  mfa_methods: z.array(z.string()).optional(),
  billing_redirect: billingRedirectSchema.optional(),
});

/**
 * Error response with optional field-level error details.
 * field-error tuple: [field_name, error_message]
 */
const authErrorSchema = z.object({
  error: z.string(),
  'field-error': z.tuple([z.string(), z.string()]).optional(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Composite Response Schemas
// ─────────────────────────────────────────────────────────────────────────────

/** Standard auth response for endpoints that don't return MFA data */
const authResponseSchema = z.union([authSuccessSchema, authErrorSchema]);

/**
 * Login response schema - supports MFA and billing redirect flows.
 *
 * IMPORTANT: Schema union order matters - Zod matches first valid schema.
 * Order from most to least specific:
 * 1. MFA required (has mfa_required) - most specific
 * 2. Billing redirect (has billing_redirect) - moderately specific
 * 3. Plain success - least specific
 */
export const loginResponseSchema = z.union([
  authSuccessWithMfaSchema,     // Most specific - has mfa_required
  authSuccessWithBillingSchema, // Moderately specific - has billing_redirect
  authSuccessSchema,            // Least specific - just { success }
  authErrorSchema,
]);
export type LoginResponse = z.infer<typeof loginResponseSchema>;

/**
 * Signup response schema - supports billing redirect flow.
 * After account creation, user may be redirected to checkout.
 */
export const createAccountResponseSchema = z.union([
  authSuccessWithBillingSchema, // Has billing_redirect
  authSuccessSchema,            // Just { success }
  authErrorSchema,
]);
export type CreateAccountResponse = z.infer<typeof createAccountResponseSchema>;

// Logout response
export const logoutResponseSchema = authResponseSchema;
export type LogoutResponse = z.infer<typeof logoutResponseSchema>;

// Password reset request response
export const resetPasswordRequestResponseSchema = authResponseSchema;
export type ResetPasswordRequestResponse = z.infer<typeof resetPasswordRequestResponseSchema>;

// Password reset (with key) response
export const resetPasswordResponseSchema = authResponseSchema;
export type ResetPasswordResponse = z.infer<typeof resetPasswordResponseSchema>;

// Type guard to check if response is an error
export function isAuthError(
  response:
    | LoginResponse
    | CreateAccountResponse
    | LogoutResponse
    | ResetPasswordRequestResponse
    | ResetPasswordResponse
    | VerifyAccountResponse
    | ChangePasswordResponse
    | CloseAccountResponse
    | EmailChangeRequestResponse
    | EmailChangeConfirmResponse
): response is z.infer<typeof authErrorSchema> {
  return 'error' in response;
}

// Verify account response
export const verifyAccountResponseSchema = authResponseSchema;
export type VerifyAccountResponse = z.infer<typeof verifyAccountResponseSchema>;

// Change password response
export const changePasswordResponseSchema = authResponseSchema;
export type ChangePasswordResponse = z.infer<typeof changePasswordResponseSchema>;

// Close account response
export const closeAccountResponseSchema = authResponseSchema;
export type CloseAccountResponse = z.infer<typeof closeAccountResponseSchema>;

// Type guard to check if response is a success
export function isAuthSuccess(
  response:
    | LoginResponse
    | CreateAccountResponse
    | LogoutResponse
    | ResetPasswordRequestResponse
    | ResetPasswordResponse
    | VerifyAccountResponse
    | ChangePasswordResponse
    | CloseAccountResponse
): response is z.infer<typeof authSuccessSchema> {
  return 'success' in response;
}

// Type guard to check if login response requires MFA
export function requiresMfa(
  response: LoginResponse
): response is z.infer<typeof authSuccessWithMfaSchema> {
  return 'success' in response && 'mfa_required' in response && response.mfa_required === true;
}

// Type guard to check if response has a valid billing redirect.
// Narrows to a type where billing_redirect is REQUIRED (not optional).
export function hasBillingRedirect(
  response: LoginResponse | CreateAccountResponse
): response is { success: string; billing_redirect: BillingRedirect } {
  return (
    'success' in response &&
    'billing_redirect' in response &&
    response.billing_redirect !== undefined &&
    response.billing_redirect.valid === true
  );
}

/**
 * Extended schemas for advanced Rodauth features
 */

// Lockout information for enhanced error responses
export const lockoutInfoSchema = z.object({
  locked: z.boolean(),
  attempts_remaining: z.number().optional(),
  unlock_at: z.string().optional(),
});

// Enhanced error schema with lockout information
export const lockoutErrorSchema = z.object({
  error: z.string(),
  'field-error': z.tuple([z.string(), z.string()]).optional(),
  lockout: lockoutInfoSchema.optional(),
});

// Active session schema
export const sessionSchema = z.object({
  id: z.string(),
  created_at: z.string(),
  last_activity_at: z.string(),
  ip_address: z.string().nullable(),
  user_agent: z.string().nullable(),
  is_current: z.boolean(),
  remember_enabled: z.boolean(),
});

// Active sessions list response
export const activeSessionsResponseSchema = z.object({
  sessions: z.array(sessionSchema),
});
export type ActiveSessionsResponse = z.infer<typeof activeSessionsResponseSchema>;

// Remove session response
export const removeSessionResponseSchema = authResponseSchema;
export type RemoveSessionResponse = z.infer<typeof removeSessionResponseSchema>;

// OTP setup response
// When HMAC is enabled, Rodauth returns an error response with only secrets on first request
export const otpSetupResponseSchema = z.object({
  qr_code: z.string().optional(), // Not present in HMAC first request
  secret: z.string().optional(), // Not present in HMAC first request
  otp_setup: z.string().optional(), // HMAC'd secret (when HMAC enabled)
  otp_raw_secret: z.string().optional(), // Raw secret (when HMAC enabled)
  otp_secret: z.string().optional(), // Alternative field name for HMAC'd secret
  error: z.string().optional(), // Error message (expected on first request with HMAC)
  'field-error': z.tuple([z.string(), z.string()]).optional(), // Field-level error
});
export type OtpSetupResponse = z.infer<typeof otpSetupResponseSchema>;

// OTP enable response (includes recovery codes)
export const otpEnableResponseSchema = z.union([
  authSuccessSchema.extend({
    recovery_codes: z.array(z.string()).optional(),
  }),
  authErrorSchema,
]);
export type OtpEnableResponse = z.infer<typeof otpEnableResponseSchema>;

// OTP disable response
export const otpToggleResponseSchema = authResponseSchema;
export type OtpToggleResponse = z.infer<typeof otpToggleResponseSchema>;

// OTP verification response
export const otpVerifyResponseSchema = authResponseSchema;
export type OtpVerifyResponse = z.infer<typeof otpVerifyResponseSchema>;

// Recovery code schema
export const recoveryCodeSchema = z.object({
  code: z.string(),
  used: z.boolean(),
  used_at: z.string().optional(),
});

// Recovery codes response
export const recoveryCodesResponseSchema = z.object({
  codes: z.array(z.string()),
});
export type RecoveryCodesResponse = z.infer<typeof recoveryCodesResponseSchema>;

// Account information response
export const accountInfoResponseSchema = z.object({
  id: z.number(),
  email: z.string(),
  created_at: z.string(),
  status: z.number(),
  email_verified: z.boolean(),
  mfa_enabled: z.boolean(),
  recovery_codes_count: z.number(),
  passkeys_count: z.number().optional(),
});
export type AccountInfoResponse = z.infer<typeof accountInfoResponseSchema>;

// MFA status response
export const mfaStatusResponseSchema = z.object({
  enabled: z.boolean(),
  last_used_at: z.string().nullable(),
  recovery_codes_remaining: z.number(),
  recovery_codes_limit: z.number(),
});
export type MfaStatusResponse = z.infer<typeof mfaStatusResponseSchema>;

// Email change request response
export const emailChangeRequestResponseSchema = authResponseSchema;
export type EmailChangeRequestResponse =
  z.infer<typeof emailChangeRequestResponseSchema>;

// Email change confirmation response
export const emailChangeConfirmResponseSchema = authResponseSchema;
export type EmailChangeConfirmResponse =
  z.infer<typeof emailChangeConfirmResponseSchema>;
