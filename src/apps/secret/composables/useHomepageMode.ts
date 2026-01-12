// src/apps/secret/composables/useHomepageMode.ts

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { storeToRefs } from 'pinia';
import { computed } from 'vue';

export type HomepageMode = 'open' | 'internal' | 'external';

export function useHomepageMode() {
  const bootstrapStore = useBootstrapStore();
  const { homepage_mode } = storeToRefs(bootstrapStore);

  const mode = computed<HomepageMode>(() => (homepage_mode.value as HomepageMode) || 'open');

  const isDisabled = computed(() => mode.value === 'external');
  const isInternal = computed(() => mode.value === 'internal');
  const isOpen = computed(() => mode.value === 'open');

  const options = computed(() => ({
    showInternalWarning: isInternal.value,
    allowCreation: !isDisabled.value,
  }));

  return {
    mode,
    isDisabled,
    isInternal,
    isOpen,
    options,
  };
}
