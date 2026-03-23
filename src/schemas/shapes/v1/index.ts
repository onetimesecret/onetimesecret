// src/schemas/shapes/v1/index.ts
//
// V1 wire-format shapes for legacy API compatibility.
//
// V1 uses v0.23.x vocabulary and type contracts:
// - "metadata" instead of "receipt"
// - "received/viewed" instead of "revealed/previewed"
// - Integer timestamps (not Date objects)
// - String-encoded fields from Redis

export * from './secret';
