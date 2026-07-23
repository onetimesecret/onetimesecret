// src/schemas/api/auth/responses/auth.ts

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
    | EmailChangeResendResponse
    | ResendVerificationEmailResponse
    | IdentitiesResponse
    | RemoveIdentityResponse
    | LinkSsoChallengeResponse
    | LinkSsoVerifyResponse
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
    // RemoveIdentityResponse is a { success } | { error } union, so the success
    // guard sensibly applies. IdentitiesResponse is deliberately NOT included:
    // it is a { identities: [...] } list container with neither field.
    | RemoveIdentityResponse
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

// ─────────────────────────────────────────────────────────────────────────────
// Connected Identities (SSO account-linking — #3840 Phase 2)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * A single SSO identity linked to the authenticated account.
 *
 * Shape mirrors GET /auth/identities EXACTLY (account-scoped rows, ordered by
 * id ascending):
 * - id:       account_identities row PK — the stable DELETE handle.
 * - provider: strategy name stored on the row (oidc, entra, github, google).
 * - issuer:   resolved IdP issuer (Phase 0 column). '' sentinel for legacy rows
 *             and OAuth2-only providers (GitHub/Google); a URL otherwise. NOT
 *             NULL, so an empty string — never null — signals "no issuer".
 * - uid:      MASKED IdP subject (first4 + U+2026 + last4, or '***' when
 *             length <= 8). Display-only; the raw sub is never returned. The
 *             delete handle is `id`, not `uid`.
 *
 * NOTE: created_at is deliberately ABSENT — no such column exists on
 * account_identities in migration 006/008 or the spec schema. Adding a
 * timestamp would require a schema migration first.
 */
export const connectedIdentitySchema = z.object({
  id: z.number().int(),
  provider: z.string(),
  issuer: z.string(),
  uid: z.string(),
});
export type ConnectedIdentity = z.infer<typeof connectedIdentitySchema>;

/** GET /auth/identities → { identities: [...] }. Empty account => { identities: [] }. */
export const identitiesResponseSchema = z.object({
  identities: z.array(connectedIdentitySchema),
});
export type IdentitiesResponse = z.infer<typeof identitiesResponseSchema>;

/**
 * DELETE /auth/identities/:id → { success: string } on 200.
 * Error bodies (401/404/409/500) surface as the axios error's response.data and
 * are classified by useAsyncHandler; the 409 last-credential guard carries an
 * additional { error_code: 'last_credential' } the composable reads from
 * details.
 */
export const removeIdentityResponseSchema = z.union([authSuccessSchema, authErrorSchema]);
export type RemoveIdentityResponse = z.infer<typeof removeIdentityResponseSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Sign-in interstitial (SSO password-challenge linking — #3840 Phase 3)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Challenge context for the sign-in interstitial.
 *
 * An UNAUTHENTICATED SSO sign-in whose IdP email matches an existing account
 * that HAS a password is redirected by the backend to the interstitial carrying
 * a single-use challenge token. GET /auth/link-sso/:token returns the display
 * context: which provider was used and the email that was claimed. Both are
 * DISPLAY-ONLY — no secrets, no account id, no uid. The token itself is the
 * authorization; a missing / expired / consumed token is a 404 (or an error
 * body) and never returns context.
 *
 * INVARIANT (#3840): email may LOCATE an account; only a demonstrated credential
 * may BIND an identity. Here the credential is the account's EXISTING password,
 * collected by the interstitial and verified by POST /auth/link-sso.
 */
export const linkSsoChallengeSchema = z.object({
  provider: z.string(),
  email: z.string(),
});
export type LinkSsoChallenge = z.infer<typeof linkSsoChallengeSchema>;

/**
 * GET /auth/link-sso/:token → { provider, email } on 200.
 * A spent / expired / unknown token surfaces as an axios error (404/410) whose
 * body is classified by useAsyncHandler; the union's error branch only covers
 * the unusual 200-with-error body.
 */
export const linkSsoChallengeResponseSchema = z.union([linkSsoChallengeSchema, authErrorSchema]);
export type LinkSsoChallengeResponse = z.infer<typeof linkSsoChallengeResponseSchema>;

/**
 * POST /auth/link-sso non-MFA success body: the backend verified the password,
 * bound (provider, issuer, uid) to the located account, and ESTABLISHED THE
 * SESSION. It returns an optional internal redirect target; the SPA validates it
 * with isValidInternalPath and falls back to the ?redirect query param, then '/'.
 */
const linkSsoVerifyCompleteSchema = z.object({
  success: z.string(),
  redirect: z.string().optional(),
});

/**
 * POST /auth/link-sso success body.
 *
 * Because the backend completes the password check via the SAME rodauth login
 * path as POST /auth/login, it returns the STANDARD login success contract, in
 * two variants:
 * - MFA account: the same body login returns for MFA (authSuccessWithMfaSchema) —
 *   password proven, but a second factor is still required. mfa_required MUST be
 *   modelled here; a plain z.object would silently strip it and the interstitial
 *   would mark the user fully authenticated, skipping the OTP challenge (#3840).
 * - Non-MFA account: { success, redirect? } — session established.
 *
 * Union order matters (Zod matches the first valid schema): the MFA variant
 * carries the required mfa_required key and MUST precede the plain success
 * variant, which would otherwise match an MFA body and drop the flag.
 *
 * Failure bodies (401 invalid_password wrong password, 401 link_expired expired-
 * or-spent token) are NOT modelled here — they arrive as axios errors and are
 * distinguished by the composable via HTTP status + an optional { error_code }.
 */
export const linkSsoVerifySuccessSchema = z.union([
  authSuccessWithMfaSchema, // MFA variant — must precede plain success
  linkSsoVerifyCompleteSchema, // { success, redirect? }
]);
export type LinkSsoVerifySuccess = z.infer<typeof linkSsoVerifySuccessSchema>;

/** Type guard: a link-sso verify success that still requires a second factor. */
export function linkSsoRequiresMfa(
  response: LinkSsoVerifySuccess
): response is z.infer<typeof authSuccessWithMfaSchema> {
  return 'mfa_required' in response && response.mfa_required === true;
}

export const linkSsoVerifyResponseSchema = z.union([linkSsoVerifySuccessSchema, authErrorSchema]);
export type LinkSsoVerifyResponse = z.infer<typeof linkSsoVerifyResponseSchema>;

// OTP setup response
// When HMAC is enabled, Rodauth returns an error response with only secrets on first request
export const otpSetupResponseSchema = z.object({
  qr_code: z.string().optional(), // Not present in HMAC first request
  secret: z.string().optional(), // Not present in HMAC first request
  // Backend's authoritative otpauth:// provisioning URI (Rodauth's
  // otp_provisioning_uri). The frontend renders this directly as a QR code
  // rather than reconstructing the URI client-side (issue #3431).
  provisioning_uri: z.string().optional(),
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
// Backend returns { sent: true } on success (not { success: string })
const emailChangeRequestSuccessSchema = z.object({
  sent: z.boolean(),
});
export const emailChangeRequestResponseSchema = z.union([
  emailChangeRequestSuccessSchema,
  authErrorSchema,
]);
export type EmailChangeRequestResponse =
  z.infer<typeof emailChangeRequestResponseSchema>;

// Email change confirmation response
// Backend returns { confirmed: true, redirect: '/signin' } on success
const emailChangeConfirmSuccessSchema = z.object({
  confirmed: z.boolean(),
  redirect: z.string(),
});
export const emailChangeConfirmResponseSchema = z.union([
  emailChangeConfirmSuccessSchema,
  authErrorSchema,
]);
export type EmailChangeConfirmResponse =
  z.infer<typeof emailChangeConfirmResponseSchema>;

// Email change resend confirmation response
// Backend returns { sent: true, resend_count: number } on success
const emailChangeResendSuccessSchema = z.object({
  sent: z.boolean(),
  resend_count: z.number(),
});
export const emailChangeResendResponseSchema = z.union([
  emailChangeResendSuccessSchema,
  authErrorSchema,
]);
export type EmailChangeResendResponse =
  z.infer<typeof emailChangeResendResponseSchema>;

// Resend verification email response.
// ANTI-ENUMERATION: backend returns an identical { sent: true } for every
// account state (sent / throttled / verified / nonexistent). No resend_count.
const resendVerificationEmailSuccessSchema = z.object({
  sent: z.boolean(),
});
export const resendVerificationEmailResponseSchema = z.union([
  resendVerificationEmailSuccessSchema,
  authErrorSchema,
]);
export type ResendVerificationEmailResponse =
  z.infer<typeof resendVerificationEmailResponseSchema>;
