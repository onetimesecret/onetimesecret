// src/schemas/config/section/mail.ts

/**
 * Mail Configuration Schema
 *
 * Maps to the `emailer:` and `mail:` sections in config.defaults.yaml
 */

import { z } from 'zod/v4';
import { nullableString } from '../shared/primitives';

/**
 * Emailer (SMTP) configuration
 */
const emailerSchema = z.object({
  mode: z.string().default('smtp'),
  region: z.string().optional(),
  from: z.string().default('CHANGEME@example.com'),
  from_name: z.string().default('Support'),
  reply_to: nullableString,
  host: z.string().default('smtp.provider.com'),
  port: z.number().int().positive().default(587),
  user: nullableString,
  pass: nullableString,
  auth: nullableString, // 'login', 'plain', etc.
  tls: z.boolean().nullable().optional(),
});

/**
 * Truemail logger configuration
 */
const truemailLoggerSchema = z.object({
  tracking_event: z.string().default(':error'),
  stdout: z.boolean().default(true),
  log_absolute_path: z.string().optional(),
});

/**
 * Truemail validation configuration
 */
const truemailSchema = z.object({
  default_validation_type: z.string().default(':regex'),
  verifier_email: z.string().default('CHANGEME@example.com'),
  verifier_domain: z.string().optional(),
  connection_timeout: z.number().optional(),
  response_timeout: z.number().optional(),
  connection_attempts: z.number().optional(),
  validation_type_for: z.record(z.string(), z.string()).optional(),
  allowed_domains_only: z.boolean().default(false),
  allowed_emails: z.array(z.string()).optional(),
  blocked_emails: z.array(z.string()).optional(),
  allowed_domains: z.array(z.string()).optional(),
  blocked_domains: z.array(z.string()).optional(),
  blocked_mx_ip_addresses: z.array(z.string()).optional(),
  dns: z.array(z.string()).default(['1.1.1.1', '8.8.4.4', '208.67.220.220']),
  smtp_port: z.number().int().positive().optional(),
  smtp_fail_fast: z.boolean().default(false),
  smtp_safe_check: z.boolean().default(true),
  not_rfc_mx_lookup_flow: z.boolean().default(false),
  email_pattern: z.string().optional(),
  smtp_error_body_pattern: z.string().optional(),
  logger: truemailLoggerSchema.optional(),
});

/**
 * Mail validation configuration
 */
const mailSchema = z.object({
  truemail: truemailSchema.optional(),
});

/**
 * Combined mail connection schema (for static config)
 */
const mailConnectionSchema = z.object({
  mode: z.string().default('smtp'),
  auth: z.string().default('login'),
  region: z.string().optional(),
  from: z.string().default('noreply@example.com'),
  fromname: z.string().default('OneTimeSecret'),
  host: z.string().optional(),
  port: z.number().optional(),
  user: nullableString,
  pass: nullableString,
  tls: z.boolean().nullable().optional(),
});

/**
 * Mail validation schema (for static config)
 */
const mailValidationSchema = z.object({
  default_validation_type: z.string().default('mx'),
  verifier_email: z.string().default('example@onetimesecret.dev'),
  verifier_domain: z.string().default('onetimesecret.dev'),
  connection_timeout: z.number().optional(),
  response_timeout: z.number().optional(),
  connection_attempts: z.number().optional(),
  validation_type_for: z.record(z.string(), z.union([z.string(), z.any()])).optional(),
  allowed_domains_only: z.boolean().optional(),
  allowed_emails: z.array(z.string()).optional(),
  blocked_emails: z.array(z.string()).optional(),
  allowed_domains: z.array(z.string()).optional(),
  blocked_domains: z.array(z.string()).optional(),
  blocked_mx_ip_addresses: z.array(z.string()).optional(),
  dns: z.array(z.string()).optional(),
  smtp_port: z.number().optional(),
  smtp_fail_fast: z.boolean().optional(),
  smtp_safe_check: z.boolean().optional(),
  not_rfc_mx_lookup_flow: z.boolean().optional(),
  logger: z.object({
    tracking_event: z.string().default('all'),
    stdout: z.boolean().default(true),
    log_absolute_path: z.string().optional(),
  }).optional(),
});

export {
  emailerSchema,
  mailSchema,
  truemailSchema,
  mailConnectionSchema,
  mailValidationSchema,
};
