/**
 * Authentication and account management type definitions
 * Used across authentication components, composables, and views
 */

/**
 * Active session information
 */
export interface Session {
  id: string;
  created_at: string;
  last_activity_at: string;
  ip_address?: string;
  user_agent?: string;
  is_current: boolean;
  remember_enabled: boolean;
}

/**
 * Account lockout status
 */
export interface LockoutStatus {
  locked: boolean;
  attempts_remaining?: number;
  unlock_at?: string;
}

/**
 * OTP setup data from backend
 * When HMAC is enabled, includes otp_setup and otp_raw_secret
 */
export interface OtpSetupData {
  qr_code?: string;
  secret?: string;
  provisioning_uri?: string;
  otp_setup?: string; // HMAC'd secret (when HMAC enabled)
  otp_raw_secret?: string; // Raw secret (when HMAC enabled)
  otp_secret?: string; // Alternative field name
  error?: string; // Error message if setup fails
  'field-error'?: [string, string] | Record<string, string>; // Field-specific errors (tuple or object)
}

/**
 * Recovery code with usage tracking
 */
export interface RecoveryCode {
  code: string;
  used: boolean;
  used_at?: string;
}

/**
 * Comprehensive account information
 */
export interface AccountInfo {
  id: number;
  email: string;
  created_at: string;
  status: number;
  email_verified: boolean;
  mfa_enabled: boolean;
  recovery_codes_count: number;
  active_sessions_count?: number;
}

/**
 * MFA status and configuration
 */
export interface MfaStatus {
  enabled: boolean;
  last_used_at: string | null;
  recovery_codes_remaining: number;
}
