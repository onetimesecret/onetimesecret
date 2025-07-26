// src/schemas/config/section/site.ts

import { z } from 'zod/v4';

const siteAuthenticationSchema = z.object({
  enabled: z.boolean().default(false),
  colonels: z.array(z.string()).default([]),
  autoverify: z.boolean().default(false),
});

const siteMiddlewareSchema = z.object({
  static_files: z.boolean().default(true),
  utf8_sanitizer: z.boolean().default(true),
  http_origin: z.boolean().optional(),
  escaped_params: z.boolean().optional(),
  xss_header: z.boolean().optional(),
  frame_options: z.boolean().optional(),
  path_traversal: z.boolean().optional(),
  cookie_tossing: z.boolean().optional(),
  ip_spoofing: z.boolean().optional(),
  strict_transport: z.boolean().optional(),
});

const siteSchema = z.object({
  host: z.string().default('localhost:3000'),
  ssl: z.boolean().default(false),
  secret: z.string().default('CHANGEME'),
  authentication: siteAuthenticationSchema,
  middleware: siteMiddlewareSchema,
});

export { siteSchema };
