/**
 * Composable for footer configuration derived from bootstrap store.
 *
 * Centralizes access to deployment-level footer settings (e.g., show_version)
 * so all footer components respect the same server config.
 */
import { computed } from 'vue';
import { storeToRefs } from 'pinia';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';

export function useFooterConfig() {
  const bootstrapStore = useBootstrapStore();
  const { ui, authenticated } = storeToRefs(bootstrapStore);

  /**
   * Whether to show version info in footer.
   * Controlled by FOOTER_VERSION_ENABLED env var via ui.show_version.
   * Defaults to true when not configured.
   */
  const showVersionConfig = computed(() => ui.value?.show_version ?? true);

  /**
   * Whether to render the version string in the footer.
   * Exposing the exact deployment version to anonymous visitors makes it
   * easier to fingerprint the install and target known CVEs, so this is
   * additionally restricted to authenticated sessions.
   */
  const showVersion = computed(() => showVersionConfig.value && authenticated.value === true);

  return {
    showVersionConfig,
    showVersion,
  };
}
