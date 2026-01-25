// src/schemas/api/index.ts

//
// - auth/      - Shared authentication schemas (JSON-typed)
// - v3/        - Public API with JSON-typed responses (current)
// - account/   - Site-only account endpoints (JSON-typed)

export * as auth from './auth';
export * as v3 from './v3';
export * as account from './account';
