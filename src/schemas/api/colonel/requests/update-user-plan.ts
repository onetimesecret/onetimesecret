// src/schemas/api/colonel/requests/update-user-plan.ts
//
// Request schema for ColonelAPI::Logic::Colonel::UpdateUserPlan
// POST /users/:user_id/plan
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// user_id is in path param.

import { z } from 'zod';

export const updateUserPlanRequestSchema = z.object({
  /** Plan identifier from billing catalog */
  planid: z.string(),
});

export type UpdateUserPlanRequest = z.infer<typeof updateUserPlanRequestSchema>;
