// src/schemas/config/section/mail.ts

import { z } from 'zod/v4';

const nullableString = z.string().nullable().optional();

const mailValidationSchema = z.object({
  default_validation_type: z.string().default('mx'),
  verifier_email: z.email().default('example@onetimesecret.dev'),
  verifier_domain: z.string().default('onetimesecret.dev'),
  connection_timeout: z.number().optional(),
  response_timeout: z.number().optional(),
  connection_attempts: z.number().optional(),
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
  logger: z
    .object({
      tracking_event: z.string().default('all'),
      stdout: z.boolean().default(true),
      log_absolute_path: z.string().optional(),
    })
    .optional(),
});

const mailConnectionSchema = z.object({
  mode: z.string().default('smtp'),
  auth: z.string().default('login'),
  region: z.string().optional(),
  from: z.email().optional().default('noreply@example.com'),
  fromname: z.string().default('OneTimeSecret'),
  host: z.string().optional(),
  port: z.number().optional(),
  user: nullableString,
  pass: nullableString,
  tls: z.boolean().nullable().optional(),
});

export { mailConnectionSchema, mailValidationSchema };
