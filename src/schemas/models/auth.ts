// src/schemas/models/auth.ts

/**
 * Authentication Zod schemas and derived types
 *
 * Schemas are the source of truth for auth data structures.
 * Types are inferred from schemas using z.infer<>.
 */

import { z } from 'zod';

/**
 * Active session schema
 */
export const sessionSchema = z.object({
  id: z.string(),
  created_at: z.string(),
  last_activity_at: z.string(),
  ip_address: z.string().optional(),
  user_agent: z.string().optional(),
  is_current: z.boolean(),
  remember_enabled: z.boolean(),
});

export type Session = z.infer<typeof sessionSchema>;

/**
 * Account lockout status schema
 */
export const lockoutStatusSchema = z.object({
  locked: z.boolean(),
  attempts_remaining: z.number().optional(),
  unlock_at: z.string().optional(),
});

export type LockoutStatus = z.infer<typeof lockoutStatusSchema>;

/**
 * OTP setup data schema
 *
 * When HMAC is enabled, includes otp_setup and otp_raw_secret
 */
export const otpSetupDataSchema = z.object({
  qr_code: z.string().optional(),
  secret: z.string().optional(),
  provisioning_uri: z.string().optional(),
  otp_setup: z.string().optional(), // HMAC'd secret (when HMAC enabled)
  otp_raw_secret: z.string().optional(), // Raw secret (when HMAC enabled)
  otp_secret: z.string().optional(), // Alternative field name
  error: z.string().optional(), // Error message if setup fails
  'field-error': z
    .union([z.tuple([z.string(), z.string()]), z.record(z.string(), z.string())])
    .optional(), // Field-specific errors (tuple or object)
});

export type OtpSetupData = z.infer<typeof otpSetupDataSchema>;

/**
 * Recovery code schema with usage tracking
 */
export const recoveryCodeSchema = z.object({
  code: z.string(),
  used: z.boolean(),
  used_at: z.string().optional(),
});

export type RecoveryCode = z.infer<typeof recoveryCodeSchema>;

/**
 * Comprehensive account information schema
 */
export const accountInfoSchema = z.object({
  id: z.number(),
  email: z.string(),
  created_at: z.string(),
  status: z.number(),
  email_verified: z.boolean(),
  mfa_enabled: z.boolean(),
  recovery_codes_count: z.number(),
  active_sessions_count: z.number().optional(),
  passkeys_count: z.number().optional(),
});

export type AccountInfo = z.infer<typeof accountInfoSchema>;

/**
 * MFA status and configuration schema
 */
export const mfaStatusSchema = z.object({
  enabled: z.boolean(),
  last_used_at: z.string().nullable(),
  recovery_codes_remaining: z.number(),
  recovery_codes_limit: z.number(),
});

export type MfaStatus = z.infer<typeof mfaStatusSchema>;
