// src/schemas/shapes/config/section/mail.ts

/**
 * Mail Configuration Shape
 *
 * Adds runtime defaults and port bounds on top of the type-only mail
 * contract — SMTP defaults, Truemail validation defaults, and the static
 * connection block defaults.
 *
 * @see src/schemas/contracts/config/section/mail.ts
 */

import {
  emailerSchema,
  emailProvidersSchema,
  mailConnectionSchema,
  mailSchema,
  mailValidationSchema,
  truemailSchema,
} from '@/schemas/contracts/config/section/mail';
import { augment } from '@/schemas/utils/augment';
import { z } from 'zod';

export {
  emailerSchema,
  emailProvidersSchema,
  mailConnectionSchema,
  mailSchema,
  mailValidationSchema,
  truemailSchema,
};

// These are independent TypeScript mirrors of ProviderRegistry. The Ruby
// frontend-provider parity spec reads the generated schema and requires exact
// agreement, including the non-provider delivery modes handled by Mailer.
const emailDeliveryModeSchema = z.enum([
  'ses',
  'sendgrid',
  'lettermint',
  'smtp2go',
  'smtp',
  'logger',
  'disabled',
  'none',
]);
const emailSenderProviderSchema = z.enum(['ses', 'sendgrid', 'lettermint', 'smtp2go', 'smtp']);

const emailerShape = augment(emailerSchema, {
  mode: () => emailDeliveryModeSchema.default('smtp'),
  sender_provider: () => emailSenderProviderSchema.nullable().optional(),
  from: (s) => s.default('CHANGEME@example.com'),
  from_name: (s) => s.default('Support'),
  host: (s) => s.default('smtp.provider.com'),
  port: (n) => n.int().positive().default(587),
});

const emailProvidersShape = augment(emailProvidersSchema, {
  ses: {
    region: (s) => s.default('us-east-1'),
    dkim_selector_count: (n) => n.int().positive().default(3),
    spf_include: (s) => s.default('amazonses.com'),
  },
  sendgrid: {
    subdomain: (s) => s.default('em'),
    dkim_selectors: (a) => a.default(['s1', 's2']),
    spf_include: (s) => s.default('sendgrid.net'),
  },
  lettermint: {
    api_base_url: (s) => s.default('https://api.lettermint.co/v1'),
    dkim_selectors: (a) => a.default(['lm1', 'lm2']),
    spf_cname_prefix: (s) => s.default('lm-bounces'),
    spf_cname_target: (s) => s.default('bounces.lmta.net'),
  },
  smtp2go: {
    api_base_url: (s) => s.default('https://api.smtp2go.com/v3'),
    returnpath_subdomain: (s) => s.default('bounce'),
    tracking_subdomain: (s) => s.default('track'),
  },
});

const truemailShape = augment(truemailSchema, {
  default_validation_type: (s) => s.default(':regex'),
  verifier_email: (s) => s.default('CHANGEME@example.com'),
  allowed_domains_only: (b) => b.default(false),
  dns: (a) => a.default(['1.1.1.1', '8.8.4.4', '208.67.220.220']),
  smtp_port: (n) => n.int().positive().optional(),
  smtp_fail_fast: (b) => b.default(false),
  smtp_safe_check: (b) => b.default(true),
  not_rfc_mx_lookup_flow: (b) => b.default(false),
  logger: {
    tracking_event: (s) => s.default(':error'),
    stdout: (b) => b.default(true),
  },
});

const mailShape = augment(mailSchema, {
  truemail: {
    default_validation_type: (s) => s.default(':regex'),
    verifier_email: (s) => s.default('CHANGEME@example.com'),
    allowed_domains_only: (b) => b.default(false),
    dns: (a) => a.default(['1.1.1.1', '8.8.4.4', '208.67.220.220']),
    smtp_port: (n) => n.int().positive().optional(),
    smtp_fail_fast: (b) => b.default(false),
    smtp_safe_check: (b) => b.default(true),
    not_rfc_mx_lookup_flow: (b) => b.default(false),
    logger: {
      tracking_event: (s) => s.default(':error'),
      stdout: (b) => b.default(true),
    },
  },
});

const mailConnectionShape = augment(mailConnectionSchema, {
  mode: (s) => s.default('smtp'),
  auth: (s) => s.default('login'),
  from: (s) => s.default('noreply@example.com'),
  fromname: (s) => s.default('OneTimeSecret'),
});

const mailValidationShape = augment(mailValidationSchema, {
  default_validation_type: (s) => s.default('mx'),
  verifier_email: (s) => s.default('example@onetimesecret.dev'),
  verifier_domain: (s) => s.default('onetimesecret.dev'),
  logger: {
    tracking_event: (s) => s.default('all'),
    stdout: (b) => b.default(true),
  },
});

export {
  emailDeliveryModeSchema,
  emailerShape,
  emailProvidersShape,
  emailSenderProviderSchema,
  mailConnectionShape,
  mailShape,
  mailValidationShape,
  truemailShape,
};
