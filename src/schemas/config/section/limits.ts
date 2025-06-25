// src/schemas/config/section/limits.ts

/**
 * Rate Limits Management:
 *
 * Adding: Add new key with z.number().optional() in
 * appropriate comment group
 * Removing: Delete the line (catchall handles unknown keys gracefully)
 * Updating: Modify the key name directly
 *
 * All rate limit values are optional numeric limits (requests per time
 * window). Unknown rate limits are automatically handled via catchall for
 * backward compatibility.
 */

import { z } from 'zod/v4';

const RATE_LIMIT_KEYS = [
  // Core authentication and account operations
  'create_account',
  'update_account',
  'destroy_account',
  'authenticate_session',
  'destroy_session',
  'show_account',

  // Secret operations
  'create_secret',
  'show_secret',
  'show_metadata',
  'burn_secret',
  'attempt_secret_access',
  'failed_passphrase',

  // Domain operations
  'add_domain',
  'remove_domain',
  'list_domains',
  'get_domain',
  'verify_domain',
  'get_domain_brand',
  'get_domain_logo',
  'remove_domain_logo',
  'update_domain_brand',

  // Communication and feedback
  'email_recipient',
  'send_feedback',

  // Password reset operations
  'forgot_password_request',
  'forgot_password_reset',

  // Dashboard and UI operations
  'dashboard',
  'get_page',
  'get_image',

  // API and system operations
  'generate_apitoken',
  'check_status',
  'report_exception',
  'update_branding',
  'update_mutable_settings',
  'view_colonel',
  'external_redirect',

  // Payment operations
  'stripe_webhook',
] as const;

const rateLimitValue = z.number().optional();

const createRateLimitFields = () => {
  const fields: Record<string, typeof rateLimitValue> = {};

  // Add all defined rate limits
  RATE_LIMIT_KEYS.forEach((key) => {
    fields[key] = rateLimitValue;
  });

  return fields;
};

const limitsSchema = z.object(createRateLimitFields()).catchall(rateLimitValue);

// Rate limit types for better type safety
export type RateLimitKey = (typeof RATE_LIMIT_KEYS)[number] | string;
export type RateLimits = z.infer<typeof limitsSchema>;
export { RATE_LIMIT_KEYS };

export { limitsSchema };
