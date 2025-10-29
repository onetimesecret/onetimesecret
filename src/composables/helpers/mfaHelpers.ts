/**
 * Helper functions for MFA composable
 *
 * These utilities support the HMAC-based OTP setup flow, handling:
 * - QR code generation for authenticator apps
 * - HMAC setup data validation
 * - Response enrichment with generated assets
 */

import QRCode from 'qrcode';
import { otpSetupResponseSchema } from '@/schemas/api/endpoints/auth';
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
 * Note: userEmail is currently a placeholder. In production, this should be
 * fetched from the authenticated user's account information.
 */
export async function generateQrCode(secret: string): Promise<string> {
  const issuer = 'Onetime Secret';
  const userEmail = 'user@example.com'; // TODO: Get from user account
  const otpUrl = `otpauth://totp/${encodeURIComponent(issuer)}:${encodeURIComponent(userEmail)}?secret=${secret}&issuer=${encodeURIComponent(issuer)}`;
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
  return Boolean(
    (errorData.otp_secret || errorData.otp_setup) &&
    errorData.otp_raw_secret
  );
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

    // Generate QR code for authenticator app scanning
    if (validated.otp_raw_secret) {
      validated.qr_code = await generateQrCode(validated.otp_raw_secret);
    }

    // Ensure we have otp_setup for the verification step
    // Some backend versions may use otp_secret instead
    validated.otp_setup = validated.otp_setup || errorData.otp_secret || errorData.otp_setup;

    return validated;
  } catch (parseErr) {
    console.error('[mfaHelpers] Parse error:', parseErr);
    return null;
  }
}
