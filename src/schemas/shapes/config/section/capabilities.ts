// src/schemas/shapes/config/section/capabilities.ts

/**
 * Capabilities Configuration Shape
 *
 * The capabilities contract carries no defaults or value constraints — every
 * flag is a required boolean. The shape is a re-export so consumers can
 * import every config section from `shapes/config/section/*` uniformly.
 *
 * @see src/schemas/contracts/config/section/capabilities.ts
 */

export {
  capabilitiesSchema,
  capabilitiesSchema as capabilitiesShape,
  capabilityFlagsSchema,
  capabilityFlagsSchema as capabilityFlagsShape,
} from '@/schemas/contracts/config/section/capabilities';
