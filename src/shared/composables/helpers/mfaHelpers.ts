// src/shared/composables/helpers/mfaHelpers.ts

/**
 * Helper functions for MFA composable
 *
 * These utilities support the HMAC-based OTP setup flow, handling:
 * - QR code generation for authenticator apps
 * - HMAC setup data validation
 * - Response enrichment with generated assets
 * - Secure error message mapping to prevent information disclosure
 */

import { otpSetupResponseSchema } from '@/schemas/api/auth/responses/auth';
import type { OtpSetupData } from '@/types/auth';
import QRCode from 'qrcode';
import { captureMessage, isDiagnosticsEnabled } from '@/services/diagnostics.service';

/**
 * Renders a backend-provided otpauth:// provisioning URI as a QR code data URL
 *
 * The provisioning URI is emitted authoritatively by the backend (Rodauth's
 * `otp_provisioning_uri`, surfaced as `provisioning_uri` in the otp-setup
 * response). It already contains the correct secret and TOTP parameters
 * (issuer/algorithm/digits/period), so the frontend must NOT reconstruct the
 * URI or re-declare those parameters — doing so is what caused the QR to encode
 * the wrong secret (issue #3431). This function only renders the QR image.
 *
 * The result is scannable by authenticator apps such as Google Authenticator,
 * Authy, Microsoft Authenticator, and 1Password.
 *
 * @param provisioningUri - otpauth:// URI from the backend (`provisioning_uri`)
 * @returns Data URL (image/png) that can be used as an img src attribute
 */
export async function generateQrCode(provisioningUri: string): Promise<string> {
  return await QRCode.toDataURL(provisioningUri);
}

/**
 * Checks if a response contains valid HMAC setup data
 *
 * In HMAC mode, the backend returns a 422 status with setup secrets.
 * This function validates that the response includes both:
 * - otp_setup or otp_secret: HMAC'd secret (the actual TOTP key the
 *   authenticator must use, and the value the server validates against)
 * - otp_raw_secret: Raw secret used only for the setup handshake
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
 * 2. Renders a QR code from the backend's authoritative provisioning_uri
 * 3. Normalizes field names (otp_secret → otp_setup)
 * 4. Returns enriched data ready for user display
 *
 * @param errorData - Response data from HMAC setup (422 status)
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
export async function enrichSetupResponse(errorData: any): Promise<OtpSetupData | null> {
  try {
    // Validate response structure against expected schema
    const validated = otpSetupResponseSchema.parse(errorData);

    // Ensure we have otp_setup (the value shown for manual entry and sent back
    // on verification). When HMAC is enabled, the field may arrive as otp_secret.
    validated.otp_setup = validated.otp_setup || errorData.otp_secret || errorData.otp_setup;

    // Render the QR from the backend's authoritative provisioning URI so the
    // encoded secret/params always match what the server validates (#3431).
    // provisioning_uri is always present on the HMAC path; its absence means a
    // backend/frontend version skew. Fail loudly instead of returning setup
    // data with no QR, which would leave the user on a blank scan step with no
    // error (issue #3431 follow-up).
    if (!validated.provisioning_uri) {
      console.error(
        '[mfaHelpers] HMAC setup response is missing provisioning_uri; cannot render QR code'
      );
      if (isDiagnosticsEnabled()) {
        captureMessage('MFA setup response missing provisioning_uri', {
          service: 'web',
          errorType: 'technical',
        });
      }
      return null;
    }

    validated.qr_code = await generateQrCode(validated.provisioning_uri);

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
