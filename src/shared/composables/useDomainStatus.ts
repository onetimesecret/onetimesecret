// src/shared/composables/useDomainStatus.ts

import type { CustomDomain } from '@/schemas/shapes/v3';
import { computed, type MaybeRefOrGetter, toValue } from 'vue';
import { useI18n } from 'vue-i18n';

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

  const displayStatus = computed(() => {
    if (!toValue(domain)) return '';
    if (isActive.value) return t('web.STATUS.active');
    if (isWarning.value) return t('web.STATUS.dns_incorrect');
    return t('web.STATUS.inactive');
  });

  const isWarning = computed(() => toValue(domain)?.vhost?.status === 'DNS_INCORRECT');

  const isError = computed(() => !!toValue(domain) && !isActive.value && !isWarning.value);

  const statusIcon = computed(() => {
    if (isActive.value) return 'check-circle';
    if (isWarning.value) return 'alert-circle';
    return 'close-circle';
  });

  const statusColor = computed(() => {
    if (isActive.value) return 'text-green-600';
    if (isWarning.value) return 'text-yellow-600';
    return 'text-red-600';
  });

  return {
    isActive,
    isWarning,
    isError,
    displayStatus,
    statusIcon,
    statusColor,
  };
}
