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

// Error response schema with optional field-level errors
const authErrorSchema = z.object({
  error: z.string(),
  'field-error': z.tuple([z.string(), z.string()]).optional(),
});

// Union type for auth responses (can be success or error)
const authResponseSchema = z.union([authSuccessSchema, authErrorSchema]);

// Login response
export const loginResponseSchema = authResponseSchema;
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
export function isAuthError(response: LoginResponse | CreateAccountResponse | LogoutResponse | ResetPasswordRequestResponse | ResetPasswordResponse): response is z.infer<typeof authErrorSchema> {
  return 'error' in response;
}

// Type guard to check if response is a success
export function isAuthSuccess(response: LoginResponse | CreateAccountResponse | LogoutResponse | ResetPasswordRequestResponse | ResetPasswordResponse): response is z.infer<typeof authSuccessSchema> {
  return 'success' in response;
}
