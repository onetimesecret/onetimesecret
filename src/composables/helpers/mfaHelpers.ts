/**
 * Helper functions for MFA composable
 */

import QRCode from 'qrcode';
import { otpSetupResponseSchema } from '@/schemas/api/endpoints/auth';
import type { OtpSetupData } from '@/types/auth';

/**
 * Generates a QR code data URL from an OTP secret
 */
export async function generateQrCode(secret: string): Promise<string> {
  const issuer = 'Onetime Secret';
  const userEmail = 'user@example.com'; // TODO: Get from user account
  const otpUrl = `otpauth://totp/${encodeURIComponent(issuer)}:${encodeURIComponent(userEmail)}?secret=${secret}&issuer=${encodeURIComponent(issuer)}`;
  return await QRCode.toDataURL(otpUrl);
}

/**
 * Checks if error response contains HMAC setup data
 */
export function hasHmacSetupData(errorData: any): boolean {
  return Boolean(
    (errorData.otp_secret || errorData.otp_setup) &&
    errorData.otp_raw_secret
  );
}

/**
 * Validates and enriches setup response with QR code
 */
export async function enrichSetupResponse(errorData: any): Promise<OtpSetupData | null> {
  try {
    const validated = otpSetupResponseSchema.parse(errorData);

    if (validated.otp_raw_secret) {
      validated.qr_code = await generateQrCode(validated.otp_raw_secret);
    }

    // Ensure we have otp_setup for verification
    validated.otp_setup = validated.otp_setup || errorData.otp_secret || errorData.otp_setup;

    return validated;
  } catch (parseErr) {
    console.error('[mfaHelpers] Parse error:', parseErr);
    return null;
  }
}
