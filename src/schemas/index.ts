/**
 * Schema System Architecture
 *
 * Architecture Layers:
 * ┌─────────────────┐
 * │ Vue Components  │ TypeScript types, reactive state
 * ├─────────────────┤
 * │ Store Layer     │ Pinia stores with typed state
 * ├─────────────────┤
 * │ Schema Layer    │ Zod schemas, transformations
 * ├─────────────────┤
 * │ API Transport   │ JSON over HTTP
 * ├─────────────────┤
 * │ Ruby Backend    │ Model definitions
 * ├─────────────────┤
 * │ Redis Storage   │ String-based storage
 * └─────────────────┘
 *
 * Design Principles:
 *
 * 1. Type Safety Across Boundaries
 *    - Zod schemas as single source of truth
 *    - Strict validation at API boundaries
 *    - Type inference flows through entire stack
 *    - Runtime type checking via Zod
 *
 * 2. Transformation Strategy
 *    - Transform only at API boundaries
 *    - Centralized transforms in utils/transforms.ts
 *    - Consistent string → type conversions from Redis/Ruby
 *    - Explicit error handling with context
 *
 * 3. Schema Organization
 *    - Base schemas define common patterns (base.ts)
 *    - Models grouped by domain context
 *    - Clear model relationships and inheritance
 *    - Explicit API endpoint schemas
 *
 * 4. Evolution Management
 *    - Schemas version-controlled with backend
 *    - Strict validation catches API changes
 *    - Explicit optional fields
 *    - Clear transformation audit trail
 *
 * Example Data Flow:
 * Redis → Ruby → API → Schema → Store → Component
 * (str) → (obj) → (json) → (validated) → (typed) → (display)
 */

// Exports organized by architectural layer
// Base schemas and utilities
export * from './api/base';
export * from './models/base';

// Error Flynn
export * from './errors/index';

// Core domain models
export * from './models/customer';
export * from './models/feedback';
export * from './models/metadata';
export * from './models/secret';

// Domain-specific models and endpoints
export * from './api/endpoints';
export * from './api/endpoints/colonel';
export * from './models/domain/index';

// API response types
export type {
  ApiBaseResponse,
  ApiErrorResponse,
  ApiRecordResponse,
  ApiRecordsResponse,
} from './api/base';

export type {
  AccountResponse,
  ApiTokenResponse,
  MetadataResponse,
  SecretResponse,
} from './api/responses';

export type { ColonelDetails } from './api/endpoints/colonel';

// Core model types
export type { BaseModel, CustomDomain, Customer, Feedback, Metadata, Secret } from './models';

export * from './i18n';
