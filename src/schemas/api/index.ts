// API Schema Organization
//
// - auth/      - Shared authentication schemas (JSON-typed)
// - v2/        - Public API with string-based responses (legacy)
// - v3/        - Public API with JSON-typed responses (current)
// - account/   - Site-only account endpoints (JSON-typed)

export * as auth from './auth';
export * as v2 from './v2';
export * as v3 from './v3';
export * as account from './account';
