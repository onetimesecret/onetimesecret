// V1 request schemas — frozen, not composed from payloads.
//
// V1 is deprecated. These schemas exist solely for contract testing:
// validating that V1 responses remain stable between releases. They
// use flat inline definitions (no shared payloads, no transport
// wrappers) because V1 uses flat form params and will not evolve.
// Do not refactor these to compose from v2/v3 payloads.

export * from './authcheck';
export * from './burn-secret';
export * from './create';
export * from './generate';
export * from './share';
export * from './show-receipt';
export * from './show-receipt-recent';
export * from './show-secret';
export * from './status';
