// src/schemas/models/custom-domain/vhost.ts

import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

/**
 * @fileoverview VHost schema for domain verification monitoring
 *
 * Key improvements:
 * 1. Consistent use of transforms for type conversion
 * 2. Proper date handling with transforms
 * 3. Required fields properly marked
 * 4. Clear type boundaries
 *
 * Model Organization:
 * VHost is a nested model of Domain that handles monitoring data for domain verification.
 * It exists as a separate file because:
 * 1. It has distinct validation rules and monitoring-specific fields
 * 2. It maintains separation of concerns and code organization
 * 3. It keeps Domain model focused on core domain logic
 */

/**
 * VHost monitoring schema
 * Handles domain verification monitoring data
 */
export const vhostSchema = z
  .object({
    // Required fields
    id: z.number().optional(),
    status: z.string().optional(),
    incoming_address: z.string().optional(),
    target_address: z.string().optional(),
    target_ports: z.string().optional(),

    // Boolean status fields
    apx_hit: transforms.fromString.boolean.optional(),
    has_ssl: transforms.fromString.boolean.optional(),
    is_resolving: transforms.fromString.boolean.optional(),

    // Date fields using proper transforms
    created_at: transforms.fromString.date.optional(),
    last_monitored_unix: transforms.fromNumber.secondsToDate.optional(),
    ssl_active_from: transforms.fromString.date.nullable(),
    ssl_active_until: transforms.fromString.date.nullable(),

    // Optional string fields
    dns_pointed_at: z.string().optional(),
    // Third-party passthrough: the vhost blob is Approximated's response
    // stored verbatim, and their API documents keep_host as a BOOLEAN
    // (approximated_client.rb sends `keep_host: true|false|nil`). Declaring it
    // string-only rejected the whole CustomDomainListResponse on every
    // dashboard load for any domain that carries the flag (FRONTEND-18E/197).
    // Accept both readings — this field is not ours to normalize.
    keep_host: z.union([z.string(), z.boolean()]).nullable(),
    last_monitored_humanized: z.string().optional(),
    status_message: z.string().optional(),
    user_message: z.string().optional(),
  })
  .partial(); // Allow missing fields

// Export type for use in stores/components
export type VHost = z.infer<typeof vhostSchema>;
