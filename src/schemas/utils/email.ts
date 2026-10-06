// src/schemas/utils/email.ts

/**
 * Email schema for READ contracts (records the server already accepted).
 *
 * Zod's default `z.email()` pattern is ASCII-only and allows just `_ ' + - .`
 * in the local part. The server accepts more: Truemail's pattern admits
 * `!#$%&'*+/=?^_`{|}~-` and unicode letters, and
 * `Onetime::SignupValidation::VALID_EMAIL_PATTERN` is looser still. An
 * account such as `first&last@company.com` therefore exists server-side but
 * failed the bootstrap contract on every hydration, so the SPA never reached
 * the authenticated state for that user and a single such member emptied the
 * org member list.
 *
 * Read contracts must never be stricter than what the server stores. This
 * pattern mirrors the server's `VALID_EMAIL_PATTERN`
 * (`lib/onetime/signup_validation.rb`): one `@`, a dotted domain, and none of
 * `, ;` or whitespace anywhere. Input forms may keep a stricter check.
 */

import { z } from 'zod';

/** Mirror of `Onetime::SignupValidation::VALID_EMAIL_PATTERN`. */
export const WIRE_EMAIL_PATTERN = /^[^,;@ \r\n]+@[^,@; \r\n]+\.[^,@; \r\n]+$/;

/** Email as the server stores it. Use on read contracts, not on input forms. */
export const wireEmailSchema = z.email({ pattern: WIRE_EMAIL_PATTERN });
