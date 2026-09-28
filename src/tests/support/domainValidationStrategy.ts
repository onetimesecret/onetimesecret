// src/tests/support/domainValidationStrategy.ts
//
// Drives the install-level custom-domain validation strategy in component and
// route specs. Instead of stubbing the feature predicates to a boolean (which
// would hide a wrong capability table), it swaps only the snapshot-reading
// wrappers for ones that evaluate the REAL `*Of` predicates against the
// strategy chosen by the spec.
//
// Usage:
//
//   vi.mock('@/utils/features', async (importOriginal) => {
//     const { featuresForStrategy } = await import('@tests/support/domainValidationStrategy');
//     return featuresForStrategy(await importOriginal<typeof import('@/utils/features')>());
//   });
//
//   beforeEach(() => setDomainValidationStrategy('approximated'));

import type * as Features from '@/utils/features';

export type DomainValidationStrategy = 'approximated' | 'caddy_on_demand' | 'passthrough';

export const DOMAIN_VALIDATION_STRATEGIES: readonly DomainValidationStrategy[] = [
  'approximated',
  'caddy_on_demand',
  'passthrough',
];

/** Strategies whose backend requires the TXT record (BaseStrategy#proves_ownership?). */
export const OWNERSHIP_CHECKING_STRATEGIES: readonly DomainValidationStrategy[] = [
  'approximated',
  'caddy_on_demand',
];

let currentStrategy: string | null = 'approximated';

/** Accepts any string (or null) so specs can cover unknown and absent values. */
export function setDomainValidationStrategy(strategy: string | null): void {
  currentStrategy = strategy;
}

export function featuresForStrategy(actual: typeof Features): typeof Features {
  const state = () => ({ domains: { validation_strategy: currentStrategy } });
  return {
    ...actual,
    isDomainOwnershipChecked: () => actual.isDomainOwnershipCheckedOf(state()),
    isApproximatedDomainValidation: () => actual.isApproximatedDomainValidationOf(state()),
  };
}
