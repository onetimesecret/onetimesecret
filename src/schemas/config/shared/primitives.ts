// src/schemas/config/shared/primitives.ts

import { z } from 'zod';

const nullableString = z.string().nullable().optional();

export { nullableString };
