// e2e/support/totp.ts
//
// RFC 6238 TOTP (HMAC-SHA1, 6 digits, 30 s step) on node:crypto, so a browser
// spec can enrol and complete a second factor without a static code or a new
// dependency. Matches what Rodauth's otp feature (rotp) verifies.

import { createHmac } from 'node:crypto';

const BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/** Rodauth throttles a key to one use per interval, enrolment included. */
export const TOTP_STEP_SECONDS = 30;

function base32Decode(secret: string): Buffer {
  let bits = '';
  for (const char of secret.replace(/=+$/, '').replace(/\s+/g, '').toUpperCase()) {
    const value = BASE32_ALPHABET.indexOf(char);
    if (value < 0) throw new Error(`Not a base32 character: ${char}`);
    bits += value.toString(2).padStart(5, '0');
  }
  const bytes = bits.match(/.{8}/g) ?? [];
  return Buffer.from(bytes.map((byte) => parseInt(byte, 2)));
}

/** The 6-digit code for `secret` at `atMs` (default: now). */
export function totp(secret: string, atMs: number = Date.now()): string {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(atMs / 1000 / TOTP_STEP_SECONDS)));

  const digest = createHmac('sha1', base32Decode(secret)).update(counter).digest();
  const offset = digest[digest.length - 1] & 0x0f;
  const binary = digest.readUInt32BE(offset) & 0x7fffffff;
  return (binary % 1_000_000).toString().padStart(6, '0');
}
