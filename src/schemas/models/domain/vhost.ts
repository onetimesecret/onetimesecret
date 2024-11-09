// src/schemas/models/domain/vhost.ts
import { z } from 'zod'

/**
 * @fileoverview VHost schema for domain verification monitoring
 *
 * Model Organization:
 * VHost is a nested model of Domain that handles monitoring data for domain verification.
 * It exists as a separate file because:
 * 1. It has distinct validation rules and monitoring-specific fields
 * 2. It maintains separation of concerns and code organization
 * 3. It keeps Domain model focused on core domain logic
 *
 * Validation Rules:
 * - Boolean fields for verification status
 * - Timestamp fields as strings
 * - Numeric fields for IDs and Unix timestamps
 * - Status messages as strings
 */

/**
 * VHost approximation schema
 * Handles monitoring data for domain verification
 */
export const vhostSchema = z.object({
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

// Export inferred type for use in stores/components
export type VHost = z.infer<typeof vhostSchema>
