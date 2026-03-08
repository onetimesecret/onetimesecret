// src/schemas/api/colonel/requests/list-users.ts
//
// Request schema for ColonelAPI::Logic::Colonel::ListUsers
// GET /users
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.

import { z } from 'zod';

export const listUsersRequestSchema = z.object({
  /** Page number (default 1) */
  page: z.number().int().min(1).default(1),
  /** Items per page (default 50, max 100) */
  per_page: z.number().int().min(1).max(100).default(50),
});

export type ListUsersRequest = z.infer<typeof listUsersRequestSchema>;
