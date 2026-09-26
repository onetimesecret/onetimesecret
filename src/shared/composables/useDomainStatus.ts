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

  // The status blob (`vhost.status`) says what was last seen on the network:
  // whether the name resolves here and whether a certificate is served.
  // `verified` says whether the TXT ownership check has passed. They are
  // written independently, and the blob alone must not promise more than
  // `verified` allows: a domain that lost its TXT record is demoted
  // (verified=false) while the certificate issued earlier keeps serving for
  // weeks, so the probe keeps writing ACTIVE_SSL. An unverified domain is not
  // ready on the backend (no certificate issuance or renewal, no auth URLs),
  // whatever the blob says.
  const hasActiveBlobStatus = computed(() => {
    const status = toValue(domain)?.vhost?.status;
    return status === 'ACTIVE' || status === 'ACTIVE_SSL' || status === 'ACTIVE_SSL_PROXIED';
  });

  const isVerified = computed(() => toValue(domain)?.verified === true);

  /** Resolving and serving per the blob, and ownership is confirmed. */
  const isActive = computed(() => hasActiveBlobStatus.value && isVerified.value);

  const isWarning = computed(() => toValue(domain)?.vhost?.status === 'DNS_INCORRECT');

  // PENDING_SSL is written by the caddy_on_demand status probe: the name
  // resolves but no certificate was seen. Caddy can only obtain one after the
  // ACME ask endpoint says yes, which needs the TXT check to have passed.
  const isPendingSsl = computed(() => toValue(domain)?.vhost?.status === 'PENDING_SSL');

  /**
   * Verified and resolving, first certificate not issued yet. This is the
   * normal state between a passing TXT check and the first request Caddy
   * serves for the name. Not an error and nothing for the customer to do.
   */
  const isAwaitingCertificate = computed(() => isPendingSsl.value && isVerified.value);

  /**
   * The name resolves here per the blob (active or certificate pending), but
   * ownership is not confirmed: the TXT check has not passed yet, or it
   * passed once and the record has since gone. The customer has to act, so
   * this is a "no", kept apart from `isStale` ("could not tell").
   */
  const needsOwnershipCheck = computed(
    () => (hasActiveBlobStatus.value || isPendingSsl.value) && !isVerified.value
  );

  const isError = computed(
    () =>
      !!toValue(domain) && !hasActiveBlobStatus.value && !isWarning.value && !isPendingSsl.value
  );

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

  /**
   * The customer has something to do, or the last check failed. Consumers turn
   * the status into a link to the verification screen. A verified domain that
   * is only waiting for its first certificate is deliberately not included.
   */
  const needsAttention = computed(
    () => isWarning.value || isError.value || isStale.value || needsOwnershipCheck.value
  );

  // "Unverified" is the stale label only: the last status check failed, so we
  // could not tell. An outstanding ownership check is a different state with
  // its own text, so the two stay apart for screen-reader users as well (the
  // icons that also differ are aria-hidden).
  const displayStatus = computed(() => {
    if (!toValue(domain)) return '';
    if (isStale.value) return t('web.STATUS.unverified');
    if (isActive.value) return t('web.STATUS.active');
    if (isWarning.value) return t('web.STATUS.dns_incorrect');
    if (isAwaitingCertificate.value) return t('web.STATUS.pending_ssl');
    if (needsOwnershipCheck.value) return t('web.domains.pending_verification');
    return t('web.STATUS.inactive');
  });

  const statusIcon = computed(() => {
    if (isStale.value) return 'help-circle';
    if (isActive.value) return 'check-circle';
    if (isWarning.value || needsOwnershipCheck.value) return 'alert-circle';
    if (isAwaitingCertificate.value) return 'timer-outline';
    return 'close-circle';
  });

  const statusColor = computed(() => {
    if (isStale.value) return 'text-amber-500 dark:text-amber-400';
    if (isActive.value) return 'text-emerald-600 dark:text-emerald-400';
    if (isWarning.value || needsOwnershipCheck.value) return 'text-amber-500 dark:text-amber-400';
    if (isAwaitingCertificate.value) return 'text-sky-600 dark:text-sky-400';
    return 'text-rose-600 dark:text-rose-500';
  });

  return {
    isActive,
    isWarning,
    isError,
    isAwaitingCertificate,
    needsOwnershipCheck,
    needsAttention,
    isStale,
    displayStatus,
    statusIcon,
    statusColor,
  };
}
