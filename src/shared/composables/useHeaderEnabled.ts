// src/shared/composables/useHeaderEnabled.ts

/**
 * Composable for the operator-level header gate, derived from bootstrap store.
 *
 * Centralizes the HEADER_ENABLED check so every header wrapper (Branded,
 * Management, Transactional) and MastHead share one source of truth. When
 * ui.header.enabled is explicitly false the entire <header> banner landmark
 * collapses — no empty landmark, no padding band. Absent/true config means
 * enabled: the `!== false` convention treats undefined as on. See #3362.
 */
import { computed } from 'vue';
import { storeToRefs } from 'pinia';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';

export function useHeaderEnabled() {
  const bootstrapStore = useBootstrapStore();
  const { headerConfig } = storeToRefs(bootstrapStore);

  /**
   * Operator-level header gate (HEADER_ENABLED). False only when explicitly
   * disabled; absent or true config renders the header.
   */
  const headerEnabled = computed(() => headerConfig.value?.enabled !== false);

  /**
   * Navigation sub-gate within the header (header.navigation.enabled).
   * Same `!== false` default-on convention.
   */
  const navigationEnabled = computed(() => headerConfig.value?.navigation?.enabled !== false);

  return { headerEnabled, navigationEnabled };
}
