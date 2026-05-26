// src/schemas/shapes/config/section/limits.ts

/**
 * Rate Limits Configuration Shape
 *
 * The limits contract carries no defaults or value constraints — each rate
 * limit is an optional number. The shape is a re-export so consumers can
 * import every config section from `shapes/config/section/*` uniformly.
 *
 * @see src/schemas/contracts/config/section/limits.ts
 */

export {
  limitsSchema,
  limitsSchema as limitsShape,
  RATE_LIMIT_KEYS,
} from '@/schemas/contracts/config/section/limits';

export type { RateLimitKey, RateLimits } from '@/schemas/contracts/config/section/limits';
