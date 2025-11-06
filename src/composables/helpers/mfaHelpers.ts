/**
 * Helper functions for MFA composable
 *
 * These utilities support the HMAC-based OTP setup flow, handling:
 * - QR code generation for authenticator apps
 * - HMAC setup data validation
 * - Response enrichment with generated assets
 * - Secure error message mapping to prevent information disclosure
 */

import QRCode from 'qrcode';
import { otpSetupResponseSchema } from '@/schemas/api/auth/endpoints/auth';
import type { OtpSetupData } from '@/types/auth';

/**
 * Generates a QR code data URL from an OTP secret
 *
 * Creates a standard TOTP URI that can be scanned by authenticator apps like:
 * - Google Authenticator
 * - Authy
 * - Microsoft Authenticator
 * - 1Password
 *
 * @param secret - Base32-encoded secret key for TOTP generation
 * @returns Data URL (image/png) that can be used as img src attribute
 *
 * TOTP URI format:
 * otpauth://totp/Issuer:user@example.com?secret=SECRET&issuer=Issuer
 *
 * Note: emailAddress is currently a placeholder. In production, this should be
 * fetched from the authenticated user's account information.
 */
export async function generateQrCode(
  issuer: string,
  emailAddress: string,
  secret: string
): Promise<string> {
  const otpUrl = `otpauth://totp/${encodeURIComponent(issuer)}:${encodeURIComponent(emailAddress)}?secret=${secret}&issuer=${encodeURIComponent(issuer)}`;
  return await QRCode.toDataURL(otpUrl);
}

/**
 * Checks if a response contains valid HMAC setup data
 *
 * In HMAC mode, the backend returns a 422 status with setup secrets.
 * This function validates that the response includes both:
 * - otp_setup or otp_secret: HMAC'd secret for server validation
 * - otp_raw_secret: Raw secret for QR code generation
 *
 * @param errorData - Response data from 422 status (not actually an error)
 * @returns true if response contains valid HMAC setup data
 *
 * This is used to distinguish between:
 * - Actual errors (missing required fields)
 * - HMAC setup success (422 with secrets present)
 */
export function hasHmacSetupData(errorData: any): boolean {
  return Boolean((errorData.otp_secret || errorData.otp_setup) && errorData.otp_raw_secret);
}

/**
 * Validates and enriches HMAC setup response with QR code
 *
 * Takes the 422 response from HMAC setup and:
 * 1. Validates the response schema
 * 2. Generates a QR code from the raw secret
 * 3. Normalizes field names (otp_secret → otp_setup)
 * 4. Returns enriched data ready for user display
 *
 * @param errorData - Response data from HMAC setup (422 status)
 * @param siteName - The site name to display in the authenticator app
 * @param email - The user's email address to associate with the MFA setup
 * @returns Validated and enriched OtpSetupData, or null if validation fails
 *
 * Error handling:
 * - Schema validation failures are logged and return null
 * - QR code generation failures will propagate the error
 * - Missing otp_setup field is backfilled from otp_secret
 *
 * This function is critical for the HMAC flow because it transforms
 * the "error" response into actionable setup data for the user.
 */
export async function enrichSetupResponse(
  errorData: any,
  siteName: string,
  email: string
): Promise<OtpSetupData | null> {
  try {
    // Validate response structure against expected schema
    const validated = otpSetupResponseSchema.parse(errorData);

    // Ensure we have otp_setup for the verification step. When HMAC is
    // enabled, the field name is otp_secret; otherwise otp_secret.
    validated.otp_setup = validated.otp_setup || errorData.otp_secret || errorData.otp_setup;

    // Generate QR code for authenticator app scanning
    if (validated.otp_raw_secret) {
      validated.qr_code = await generateQrCode(siteName, email, validated.otp_raw_secret);
    }

    return validated;
  } catch (parseErr) {
    console.error('[mfaHelpers] Parse error:', parseErr);
    return null;
  }
}

/**
 * Maps HTTP status codes to generic MFA error messages using i18n
 *
 * This function implements OWASP/NIST security guidelines for authentication
 * error messages by preventing information disclosure through generic responses.
 * All messages are internationalized using the `web.auth.security.*` namespace.
 *
 * SECURITY: This function does NOT accept server-provided error messages to
 * prevent information leakage. All error messages are generated from status
 * codes only.
 *
 * Security Principles:
 * ====================
 * ✗ DO NOT reveal: Which credential failed, account existence, precise timing
 * ✓ SAFE to reveal: Format requirements, general guidance, expected behavior
 *
 * @param statusCode - HTTP status code from MFA API response
 * @param t - vue-i18n translate function (from useI18n())
 * @returns Generic, security-hardened, internationalized error message
 *
 * Status Code Mappings:
 * - 401 (Unauthorized): Generic authentication failure
 * - 403 (Forbidden): Generic authentication failure (no hints about why)
 * - 404 (Not Found): Recovery code validation failure
 * - 410 (Gone): Recovery code already used
 * - 429 (Too Many Requests): Rate limiting (no precise timing disclosed)
 * - 500+ (Server Error): Generic internal error
 * - Other: Generic internal error (no passthrough)
 *
 * Examples of what NOT to say:
 * - "Incorrect password" (reveals which credential failed)
 * - "Wait 5 minutes" (reveals precise lockout timing)
 * - "Account not found" (reveals account existence)
 *
 * Examples of what IS safe:
 * - "Authentication failed. Please verify your credentials and try again."
 * - "Too many attempts. Please try again later."
 * - "Codes expire every 30 seconds" (expected behavior, not attack info)
 *
 * @see src/locales/SECURITY-TRANSLATION-GUIDE.md for complete guidelines
 */
export function mapMfaError(statusCode: number, t: (key: string) => string): string {
  switch (statusCode) {
    case 401:
    case 403:
      // Generic authentication failure - don't reveal which credential failed
      // Note: We no longer check server message for 'session' - status code only
      return t('web.auth.security.authentication_failed');

    case 404:
      // Recovery code not found - safe to indicate it's about recovery codes
      return t('web.auth.security.recovery_code_not_found');

    case 410:
      // Recovery code already used - safe expected behavior message
      return t('web.auth.security.recovery_code_used');

    case 429:
      // Rate limiting - DO NOT reveal precise timing ("wait 5 minutes")
      return t('web.auth.security.rate_limited');

    case 500:
    case 502:
    case 503:
    case 504:
      // Server errors - generic message
      return t('web.auth.security.internal_error');

    default:
      // For any other status code, default to generic internal error
      // NEVER pass through server messages to prevent information leakage
      return t('web.auth.security.internal_error');
  }
}
