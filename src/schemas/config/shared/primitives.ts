// src/schemas/config/shared/primitives.ts

import { z } from 'zod/v4';

export const nullableString = z.string().nullable().optional();

export { z };
