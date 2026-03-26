// src/schemas/index.ts
//
// Minimal barrel export for commonly shared utilities.
// Consumers should import from specific paths:
//   - @/schemas/api/v3/responses (Vue apps)
//   - @/schemas/shapes/v3/customer (specific shapes)
//   - @/schemas/contracts/config (configuration)

// API envelope utilities
export {
  createApiResponseSchema,
  createApiListResponseSchema,
  apiErrorResponseSchema,
} from './api/base';

export type {
  ApiBaseResponse,
  ApiErrorResponse,
  ApiRecordResponse,
  ApiRecordsResponse,
} from './api/base';

// Error handling
export * from './errors/index';

// i18n
export * from './i18n';

// UI schemas (forms, layouts)
export * from './ui';
