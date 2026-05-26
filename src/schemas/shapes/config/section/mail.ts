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
  mailSchema,
  truemailSchema,
  mailConnectionSchema,
  mailValidationSchema,
} from '@/schemas/contracts/config/section/mail';
import { augment } from '@/schemas/utils/augment';

export {
  emailerSchema,
  mailSchema,
  truemailSchema,
  mailConnectionSchema,
  mailValidationSchema,
};

const emailerShape = augment(emailerSchema, {
  mode: (s) => s.default('smtp'),
  from: (s) => s.default('CHANGEME@example.com'),
  from_name: (s) => s.default('Support'),
  host: (s) => s.default('smtp.provider.com'),
  port: (n) => n.int().positive().default(587),
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
  emailerShape,
  mailShape,
  truemailShape,
  mailConnectionShape,
  mailValidationShape,
};
