// src/schemas/shapes/v2/index.ts
//
// V2 API shapes (secrets, receipts, customers, feedback).

/**
 * V2 API entity shapes
 */
export * from './base';
export * from './custom-domain/index';
export * from './customer';
export * from './receipt';
export * from './secret';

/**
 * Re-exports from sibling shape directories (backward compatibility)
 */
export * from '../account';
export * from '../auth';
export * from '../config';
export * from '../organizations';

/**
 * API endpoint re-exports
 */
export * from '../../api/account/responses/account';
