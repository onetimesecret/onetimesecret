// src/shared/composables/useDomainStatus.ts

import type { CustomDomain } from '@/schemas/shapes/v3';
import { computed, type MaybeRefOrGetter, toValue } from 'vue';
import { useI18n } from 'vue-i18n';

// Treat the cache as stale when the most recent vhost fetch failed within
// this window. After it, the cached value is too old to trust either way and
// we fall back to the regular active/warning/error precedence (which itself
// was likely written before the failure window started). See issue #3080.
const STALE_FRESHNESS_WINDOW_SECONDS = 6 * 60 * 60;

export function useDomainStatus(domain: MaybeRefOrGetter<CustomDomain | null>) {
  const { t } = useI18n(); // Must be called at setup time, not in computed callbacks

  const isActive = computed(() => {
    const d = toValue(domain);
    if (!d) return false;
    const status = d.vhost?.status;
    const decision =
      status === 'ACTIVE' || status === 'ACTIVE_SSL' || status === 'ACTIVE_SSL_PROXIED';
    return decision;
  });

  const isWarning = computed(() => toValue(domain)?.vhost?.status === 'DNS_INCORRECT');

  const isError = computed(() => !!toValue(domain) && !isActive.value && !isWarning.value);

  /**
   * True when the most recent vhost-status fetch failed within the
   * staleness window. The frontend uses this to surface a "verification
   * check failed" affordance and route the user to the verify page.
   */
  const isStale = computed(() => {
    const failedAt = toValue(domain)?.vhost_fetch_failed_at;
    if (failedAt == null) return false;
    const ageSeconds = Date.now() / 1000 - Number(failedAt);
    return ageSeconds >= 0 && ageSeconds < STALE_FRESHNESS_WINDOW_SECONDS;
  });

  const displayStatus = computed(() => {
    if (!toValue(domain)) return '';
    if (isStale.value) return t('web.STATUS.unverified');
    if (isActive.value) return t('web.STATUS.active');
    if (isWarning.value) return t('web.STATUS.dns_incorrect');
    return t('web.STATUS.inactive');
  });

  const statusIcon = computed(() => {
    if (isStale.value) return 'help-circle';
    if (isActive.value) return 'check-circle';
    if (isWarning.value) return 'alert-circle';
    return 'close-circle';
  });

  const statusColor = computed(() => {
    if (isStale.value) return 'text-amber-500 dark:text-amber-400';
    if (isActive.value) return 'text-emerald-600 dark:text-emerald-400';
    if (isWarning.value) return 'text-amber-500 dark:text-amber-400';
    return 'text-rose-600 dark:text-rose-500';
  });

  return {
    isActive,
    isWarning,
    isError,
    isStale,
    displayStatus,
    statusIcon,
    statusColor,
  };
}
