// src/schemas/api/v3/index.ts
//
// V3 API: Native JSON types with improved naming.
//
// Built on V2's structure but returns proper JSON types (numbers, booleans)
// instead of strings. When schema validation fails, investigate whether the
// issue is in backend serialization, frontend schema, or stored data.
//
// Wire format: JSON with native types (numbers, booleans, nested objects).
// Timestamps: Unix epoch seconds as numbers.
// Booleans: Native true/false.

export * from './base';
export * from './requests';
export * from './requests/content';
export * from './responses';
