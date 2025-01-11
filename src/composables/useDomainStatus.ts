// src/composables/useDomainStatus.ts

import type { CustomDomain } from '@/schemas/models';
import { computed } from 'vue';

export function useDomainStatus(domain: CustomDomain) {
  const isActive = computed(() => {
    const status = domain.vhost?.status;
    const decision =
      status === 'ACTIVE' || status === 'ACTIVE_SSL' || status === 'ACTIVE_SSL_PROXIED';
    return decision;
  });

  const isWarning = computed(() => domain.vhost?.status === 'DNS_INCORRECT');

  const isError = computed(() => !isActive.value && !isWarning.value);

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
    statusIcon,
    statusColor,
  };
}
