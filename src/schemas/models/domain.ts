// src/schemas/models/domain.ts
import { z } from 'zod'
import { baseApiRecordSchema, booleanFromString } from '@/utils/transforms'
import type { BaseApiRecord } from '@/types/api/responses'
import { brandSettingsInputSchema } from './brand'

/**
 * @fileoverview Custom domain schema for API transformation boundaries
 *
 * Key Design Decisions:
 * 1. Input schemas handle API -> App transformation
 * 2. App uses single shared type between stores/components
 * 3. No explicit output schemas - serialize when needed
 *
 * Type Flow:
 * API Response (strings) -> InputSchema -> Store/Components -> API Request
 *                          ^                                ^
 *                          |                                |
 *                       transform                       serialize
 *
 * Validation Rules:
 * - Boolean fields come as strings from Ruby/Redis ('true'/'false')
 * - Domain parts must be strings
 * - Optional nested objects (vhost, brand)
 */

/**
 * VHost approximation schema
 * Handles monitoring data for domain verification
 */
export const approximatedVHostSchema = z.object({
  apx_hit: z.boolean(),
  created_at: z.string(),
  dns_pointed_at: z.string(),
  has_ssl: z.boolean(),
  id: z.number(),
  incoming_address: z.string(),
  is_resolving: z.boolean(),
  keep_host: z.string().nullable(),
  last_monitored_humanized: z.string(),
  last_monitored_unix: z.number(),
  ssl_active_from: z.string(),
  ssl_active_until: z.string(),
  status: z.string(),
  status_message: z.string(),
  target_address: z.string(),
  target_ports: z.string(),
  user_message: z.string()
})

/**
 * Input schema for custom domain from API
 * - Handles string -> boolean coercion from Ruby/Redis
 * - Validates domain parts
 * - Handles nested objects (vhost, brand)
 */
const customDomainBaseSchema = baseApiRecordSchema.extend({
  // Core identifiers
  domainid: z.string(),
  custid: z.string(),

  // Domain parts
  display_domain: z.string(),
  base_domain: z.string(),
  subdomain: z.string(),
  trd: z.string(),
  tld: z.string(),
  sld: z.string(),
  _original_value: z.string(),

  // Boolean fields that come as strings from API
  is_apex: booleanFromString,
  verified: booleanFromString,

  // Validation fields
  txt_validation_host: z.string(),
  txt_validation_value: z.string(),

  // Optional nested objects
  vhost: approximatedVHostSchema.optional(),
  brand: brandSettingsInputSchema.optional()
})

// Export the schema with passthrough
export const customDomainInputSchema = customDomainBaseSchema.passthrough()

// Export inferred types for use in stores/components
export type ApproximatedVHost = z.infer<typeof approximatedVHostSchema>
export type CustomDomain = z.infer<typeof customDomainInputSchema> & BaseApiRecord

/**
 * Input schema for domain cluster from API
 * Used for managing domain routing/infrastructure
 */
export const customDomainClusterInputSchema = baseApiRecordSchema.extend({
  identifier: z.string(),
  type: z.string(),
  cluster_ip: z.string(),
  cluster_name: z.string(),
  cluster_host: z.string(),
  vhost_target: z.string()
})

export type CustomDomainCluster = z.infer<typeof customDomainClusterInputSchema> & BaseApiRecord

// Domain strategy constants and type
export const DomainStrategyValues = {
  CANONICAL: 'canonical',
  SUBDOMAIN: 'subdomain',
  CUSTOM: 'custom',
  INVALID: 'invalid'
} as const

export type DomainStrategy = typeof DomainStrategyValues[keyof typeof DomainStrategyValues]
