import { computed } from 'vue';
import { WindowService } from '@/services/window.service';

export type HomepageMode = 'open' | 'internal' | 'external';

export function useHomepageMode() {
  const mode = computed<HomepageMode>(() => {
    return (WindowService.get('homepage_mode') as HomepageMode) || 'open';
  });

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
