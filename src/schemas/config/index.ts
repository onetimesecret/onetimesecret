// src/schemas/config/index.ts

/**
 * Configuration Schema Architecture
 *
 * This module defines two complementary schema types for application configuration:
 *
 * Static Config Schema (staticConfigSchema):
 * - Defines infrastructure topology and system capabilities
 * - Establishes the bounds of what's possible in the application
 * - Represents bootstrap configuration that sets up foundational services
 *
 * Mutable Settings Schema (mutableSettingsSchema):
 * - Defines business policies and runtime behavior
 * - Operates within the bounds established by static configuration
 * - Represents dynamic settings that can be modified during operation
 *
 * Static + Mutable -> Runtime Config.
 *
 * Design Principle:
 * Separate concerns during authoring, unify for consumption. The configuration
 * system merges these schemas at runtime, with merge priority ensuring that
 * runtime policies cannot break infrastructure constraints. This creates a
 * capability-based configuration where the runtime settings object becomes
 * the operational source of truth while respecting both infrastructure
 * topology and business rules.
 */

import { z } from 'zod/v4';
