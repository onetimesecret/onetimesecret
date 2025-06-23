// src/schemas/config/runtime.ts

import { z } from 'zod/v4';

import { configSchema as staticConfigSchema } from './static';
import { configSchema as mutableConfigSchema } from './mutable';

// const runtimeMailSchema = z.union([staticMailSchema, mutableMailSchema]);

const configSchema = z.union([staticConfigSchema, mutableConfigSchema]);

export type StaticConfig = z.infer<typeof configSchema>;
