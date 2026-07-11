// src/shared/utils/banner-visibility.ts

import type { BannerAudience } from '@/types/ui/layouts';

/**
 * Audience scope a global-broadcast banner can target. Mirrors the backend's
 * Onetime::Operations::BannerState::VALID_SCOPES and the bootstrap contract's
 * `global_banner_scope` enum.
 */
export type BannerScope = 'all' | 'no_recipient' | 'workspace';

/** Fallback scope when none is stored (matches the backend DEFAULT_SCOPE). */
export const DEFAULT_BANNER_SCOPE: BannerScope = 'no_recipient';

/**
 * Decide whether a banner with the given audience scope should show on a page of
 * the given audience and domain context. This is the single source of truth for
 * global-broadcast visibility, consumed by BaseLayout.
 *
 * Custom-domain pages are suppressed unless the operator chose 'all' (truly
 * global) — branded recipient surfaces shouldn't carry OTS-operator
 * announcements by default.
 *
 *   all           → every audience, including recipient pages + custom domains
 *   no_recipient  → every audience except recipient; never on custom domains
 *   workspace     → workspace audience only; never on custom domains
 *
 * @param scope           banner audience scope (null/unknown → DEFAULT_BANNER_SCOPE)
 * @param audience        the page's audience marker
 * @param domainStrategy  identityStore.domainStrategy for the current request
 */
export function bannerAudienceAllows(
  scope: BannerScope | null | undefined,
  audience: BannerAudience,
  domainStrategy: 'canonical' | 'subdomain' | 'custom' | 'invalid'
): boolean {
  const effectiveScope: BannerScope = scope ?? DEFAULT_BANNER_SCOPE;

  if (domainStrategy === 'custom') {
    return effectiveScope === 'all';
  }

  switch (effectiveScope) {
    case 'all':
      return true;
    case 'workspace':
      return audience === 'workspace';
    case 'no_recipient':
    default:
      return audience !== 'recipient';
  }
}
