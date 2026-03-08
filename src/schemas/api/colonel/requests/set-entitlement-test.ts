// src/schemas/api/colonel/requests/set-entitlement-test.ts
//
// Request schema for ColonelAPI::Logic::Colonel::SetEntitlementTest
// POST /entitlement-test
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.

import { z } from 'zod';

export const setEntitlementTestRequestSchema = z.object({
  /** Target user identifier */
  user_id: z.string(),
  /** Entitlement name to test */
  entitlement: z.string(),
  /** Enable or disable the entitlement */
  value: z.boolean(),
});

export type SetEntitlementTestRequest = z.infer<typeof setEntitlementTestRequestSchema>;
