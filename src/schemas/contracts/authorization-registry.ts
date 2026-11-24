import registry from './authorization-registry.json';

export type PlanFeature = keyof typeof registry.features;
export type RoleCapability = keyof typeof registry.capabilities;

export function isPlanFeature(name: string): name is PlanFeature {
  return Object.hasOwn(registry.features, name);
}

export function isRoleCapability(name: string): name is RoleCapability {
  return Object.hasOwn(registry.capabilities, name);
}

export const knownAuthorizationTokens = Object.values(registry).flatMap(Object.keys);
