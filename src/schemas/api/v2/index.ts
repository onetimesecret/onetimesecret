// src/schemas/api/v2/index.ts
//
// V2 API: Robust API with string-encoded values.
//
// All response values are strings, mirroring Redis storage format. This
// simplified backend codepaths but pushed type conversion to API consumers.
// For new integrations, prefer V3 which returns native JSON types.
//
// Wire format: JSON with string values.
// Timestamps: Unix epoch seconds as strings (e.g., "1609459200").
// Booleans: String "true"/"false" or "1"/"0".
// Numbers: String representations (e.g., "42").

export * from './requests';
export * from './requests/content';
export * from './responses';
