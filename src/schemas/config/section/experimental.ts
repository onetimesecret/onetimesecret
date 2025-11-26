// src/schemas/config/section/experimental.ts

/**
 * Experimental Configuration Schema
 *
 * Maps to the `experimental:` section in config.defaults.yaml
 */

import { z } from 'zod/v4';

/**
 * Middleware configuration
 */
const middlewareSchema = z.object({
  static_files: z.boolean().default(true),
  utf8_sanitizer: z.boolean().default(true),
  authenticity_token: z.boolean().default(true),
  http_origin: z.boolean().default(false),
  escaped_params: z.boolean().default(false),
  xss_header: z.boolean().default(false),
  frame_options: z.boolean().default(false),
  path_traversal: z.boolean().default(false),
  cookie_tossing: z.boolean().default(false),
  ip_spoofing: z.boolean().default(false),
  strict_transport: z.boolean().default(false),
});

/**
 * Content Security Policy configuration
 */
const cspSchema = z.object({
  enabled: z.boolean().default(false),
});

/**
 * Experimental features configuration
 */
const experimentalSchema = z.object({
  allow_nil_global_secret: z.boolean().default(false),
  rotated_secrets: z.array(z.string()).default([]),
  freeze_app: z.boolean().default(false),
  middleware: middlewareSchema.optional(),
  csp: cspSchema.optional(),
});

export { experimentalSchema, middlewareSchema, cspSchema };
