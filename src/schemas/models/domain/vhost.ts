// src/schemas/models/domain/vhost.ts
import { baseNestedRecordSchema } from '@/schemas/base';
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
export const vhostSchema = baseNestedRecordSchema.extend({
  apx_hit: z.boolean().optional(),
  created_at: z.string().optional(),
  dns_pointed_at: z.string().optional(),
  has_ssl: z.boolean().optional(),
  id: z.number().optional(),
  incoming_address: z.string().optional(),
  is_resolving: z.boolean().optional(),
  keep_host: z.string().nullable().optional(),
  last_monitored_humanized: z.string().optional(),
  last_monitored_unix: z.number().optional(),
  ssl_active_from: z.string().nullable().optional(),
  ssl_active_until: z.string().nullable().optional(),
  status: z.string().optional(),
  status_message: z.string().optional(),
  target_address: z.string().optional(),
  target_ports: z.string().optional(),
  user_message: z.string().optional(),
}).passthrough()

// Export inferred type for use in stores/components
export type VHost = z.infer<typeof vhostSchema>
