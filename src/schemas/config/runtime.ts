// src/schemas/config/runtime.ts

/**
 * Runtime Configuration Schema
 *
 * This module defines the schema for the runtime configuration of the application.
 * It includes mutable settings that can be modified during operation, while respecting
 * the infrastructure topology and business rules established by the static configuration.
 *
 */

import { z } from 'zod/v4';

import { configSchema as staticConfigSchema } from './static';
import { configSchema as mutableConfigSchema } from './mutable';

// const runtimeMailSchema = z.union([staticMailSchema, mutableMailSchema]);

const configSchema = z.union([staticConfigSchema, mutableConfigSchema]);

export type Config = z.infer<typeof configSchema>;

export { configSchema };
