// src/composables/useSecretState.ts

import { Metadata } from '@/schemas/models/index';
import { formatRelativeTime } from '@/utils/format/index';
import type { ComputedRef } from 'vue';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

/**
 * Icon path configurations for different states
 */
/* eslint-disable max-lines-per-function */
const iconPaths = {
  viewable: 'M3.75 13.5l10.5-11.25L12 10.5h8.25L9.75 21.75 12 13.5H3.75z',
  burned:
    'M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z',
  protected:
    'M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z',
  viewed: 'M6 18L18 6M6 6l12 12',
  destroyed:
    'M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z',
} as const;

export function useSecretState(metadata: Metadata, hasPassphrase: ComputedRef) {
  const { t } = useI18n();

  const messages = computed(() => ({
    viewable: t('web.private.created_success'),
    burned: computed(() =>
      t('web.private.burned_ago', {
        time: formatRelativeTime(metadata.burned), // timeField
      })
    ),
    received: computed(() =>
      t('web.private.viewed_ago', {
        time: formatRelativeTime(metadata.received),
      })
    ),
    protected: computed(() =>
      hasPassphrase.value
        ? t('web.private.requires_passphrase')
        : t('web.private.encrypted_message')
    ),
    destroyed: computed(() =>
      t('web.private.destroyed_ago', {
        time: formatRelativeTime(metadata.updated),
      })
    ),
  }));

  const stateConfig = computed(() => ({
    viewable: {
      icon: iconPaths.viewable,
      color: 'emerald',
      message: messages.value.viewable,
    },
    burned: {
      icon: iconPaths.burned,
      color: 'red',
      message: messages.value.burned.value,
    },
    received: {
      icon: iconPaths.viewed,
      color: 'gray',
      message: messages.value.received.value,
    },
    protected: {
      icon: iconPaths.protected,
      color: 'amber',
      message: messages.value.protected.value,
    },
    destroyed: {
      icon: iconPaths.destroyed,
      color: 'red',
      message: messages.value.destroyed.value,
    },
  }));

  return { stateConfig };
}
