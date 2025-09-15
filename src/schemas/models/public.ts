// src/schemas/models/public.ts
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

/**
 * Zod schema for SecretOptions
 *
 * @example Validate and parse the data
 *    const parsedSecretOptions: SecretOptions = secretOptionsSchema.parse(receivedSecretOptions);
 *    const parsedAuthSettings: Authentication = authenticationSchema.parse(receivedAuthSettings);
 *
 *    console.log(parsedSecretOptions);
 *       Output:
 *       {
 *         default_ttl: 604800,
 *         ttl_options: [600, 1800, 3600]
 *       }
 *
 */
export const secretOptionsSchema = z.object({
  /**
   * Default Time-To-Live (TTL) for secrets in seconds
   * Default: 604800 (7 days in seconds)
   */
  default_ttl: z
    .number()
    .int()
    .positive()
    .default(604800)
    .transform((val) => transforms.fromString.number.parse(val)),

  /**
   * Available TTL options for secret creation (in seconds)
   * These options will be presented to users when they create a new secret
   * Format: Array of integers representing seconds
   * Default: [300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600]
   */
  ttl_options: z
    .array(z.number().int().positive().min(60).max(2592000))
    .transform((arr) => arr.map((val) => transforms.fromString.number.parse(val)))
    .default([300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000]),
});

/**
 * Inferred TypeScript type for SecretOptions
 */
export type SecretOptions = z.infer<typeof secretOptionsSchema>;

/**
 * Zod schema for Authentication
 */
export const authenticationSchema = z.object({
  /**
   * Flag to enable or disable authentication
   */
  enabled: transforms.fromString.boolean,

  /**
   * Flag to allow or disallow user sign-up
   */
  signup: transforms.fromString.boolean,

  /**
   * Flag to allow or disallow user sign-in
   */
  signin: transforms.fromString.boolean,

  /**
   * Flag to enable or disable automatic verification
   */
  autoverify: transforms.fromString.boolean,

  /**
   * Flag to enable or disable homepage secret form when not logged in.
   */
  required: transforms.fromString.boolean,
});

/**
 * Inferred TypeScript type for Authentication
 */
export type AuthenticationSettings = z.infer<typeof authenticationSchema>;

/**
 * Schema for the :jurisdiction section
 */
const jurisdictionSchema = z.object({
  identifier: z.string(),
  display_name: z.string(),
  domain: z.string(),
  icon: z.string(),
});

/**
 * Schema for the :regions section
 */
const regionsSchema = z.object({
  enabled: transforms.fromString.boolean,
  current_jurisdiction: z.string().optional(),
  jurisdictions: z.array(jurisdictionSchema).optional(),
});

/**
 * Schema for the :cluster section within :domains
 */
const clusterSchema = z
  .object({
    type: z.string().optional(),
    //  api_key: z.string().optional(),
    cluster_ip: z.string().optional(),
    cluster_host: z.string().optional(),
    cluster_name: z.string(),
    vhost_target: z.string(),
  })
  .strip();

/**
 * Schema for the :domains section
 */
const domainsSchema = z.object({
  enabled: transforms.fromString.boolean,
  default: z.string().optional(),
  cluster: clusterSchema,
});

/**
 * Schema for the :authenticity section
 */
const authenticitySchema = z
  .object({
    type: z.string(),
    //  secret_key: z.string(),
  })
  .strip();

/**
 * Schema for the :support section
 */
const supportSchema = z.object({
  host: z.string().optional(),
});

/**
 * Combined Schema for PublicSettings based on :site in config.schema.yaml
 */
export const publicSettingsSchema = z
  .object({
    host: z.string(),
    domains: domainsSchema,
    ssl: transforms.fromString.boolean,
    authentication: authenticationSchema,
    // secret: z.string(),
    authenticity: authenticitySchema,
    support: supportSchema,
    regions: regionsSchema,
    secret_options: secretOptionsSchema,
  })
  .strict();

/**
 * Inferred TypeScript type for PublicSettings
 */
export type PublicSettings = z.infer<typeof publicSettingsSchema>;
