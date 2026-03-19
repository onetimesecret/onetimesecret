// src/types/auth.ts

/**
 * Authentication and account management type definitions
 *
 * Types are derived from Zod schemas in @/schemas/shapes/v2/auth.
 * Schemas are the source of truth - do not add manual interfaces here.
 */

export {
  // Schemas
  sessionSchema,
  lockoutStatusSchema,
  otpSetupDataSchema,
  recoveryCodeSchema,
  accountInfoSchema,
  mfaStatusSchema,
  // Types
  type Session,
  type LockoutStatus,
  type OtpSetupData,
  type RecoveryCode,
  type AccountInfo,
  type MfaStatus,
} from '@/schemas/shapes/v2/auth';
