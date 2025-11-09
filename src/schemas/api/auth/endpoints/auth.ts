// src/schemas/api/endpoints/auth.ts

import { z } from 'zod';

/**
 * Rodauth-compatible authentication response schemas
 *
 * Rodauth JSON API returns:
 * - Success: { success: "message" }
 * - Error: { error: "message", "field-error": ["field", "error"] }
 *
 * These schemas work with both basic and advanced authentication modes.
 */

// Success response schema
const authSuccessSchema = z.object({
  success: z.string(),
});

// Success response with MFA requirement
const authSuccessWithMfaSchema = z.object({
  success: z.string(),
  mfa_required: z.boolean(),
  mfa_auth_url: z.string().optional(),
  mfa_methods: z.array(z.string()).optional(),
});

// Error response schema with optional field-level errors
const authErrorSchema = z.object({
  error: z.string(),
  'field-error': z.tuple([z.string(), z.string()]).optional(),
});

// Union type for auth responses (can be success or error)
const authResponseSchema = z.union([authSuccessSchema, authErrorSchema]);

// Login response (can include MFA requirement)
export const loginResponseSchema = z.union([
  authSuccessSchema,
  authSuccessWithMfaSchema,
  authErrorSchema,
]);
export type LoginResponse = z.infer<typeof loginResponseSchema>;

// Signup/Create account response
export const createAccountResponseSchema = authResponseSchema;
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
});
export type AccountInfoResponse = z.infer<typeof accountInfoResponseSchema>;

// MFA status response
export const mfaStatusResponseSchema = z.object({
  enabled: z.boolean(),
  last_used_at: z.string().nullable(),
  recovery_codes_remaining: z.number(),
});
export type MfaStatusResponse = z.infer<typeof mfaStatusResponseSchema>;
