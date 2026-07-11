<!-- src/apps/workspace/components/domains/DomainAuthOverrideBanner.vue -->

<script setup lang="ts">
/**
 * Effective-state banner for the per-domain auth override settings pages
 * (sign-in and sign-up). One definition, two consumers (ADR-024).
 *
 * Renders:
 * - A status line stating the resolver's effective output ("Sign-in on this
 *   domain: Enabled"). Driven by the backend's `details.effective_enabled`,
 *   so it can never contradict the runtime gate.
 * - A "Workspace default" badge while the domain has no explicit
 *   configuration; it disappears on the first explicit action.
 * - A dormant warning when the install-level capability is off (kill
 *   switch): per-domain settings stay editable — explicit configuration
 *   still pins behavior for future default changes — but nothing runs
 *   until the workspace-wide capability is re-enabled.
 */
import { useI18n } from 'vue-i18n';
import { computed } from 'vue';
import OIcon from '@/shared/components/icons/OIcon.vue';

const props = defineProps<{
  /** Which feature's i18n namespace to use (web.domains.<feature>.*). */
  feature: 'signin' | 'signup';
  /** Resolver output for this domain; null while details are loading/absent. */
  effectiveEnabled: boolean | null;
  /** Install-level capability; null while details are loading/absent. */
  globalEnabled: boolean | null;
  /** True when the domain follows workspace defaults (no explicit config). */
  workspaceDefault: boolean;
}>();

const { t } = useI18n();

const statusLabel = computed(() => t(`web.domains.${props.feature}.effective_status_label`));
const dormantNotice = computed(() => t(`web.domains.${props.feature}.dormant_notice`));
</script>

<template>
  <div
    v-if="effectiveEnabled !== null"
    class="space-y-3"
    data-testid="auth-override-banner">
    <!-- Effective status line -->
    <div
      class="flex items-center gap-3 rounded-md bg-gray-50 px-4 py-3 dark:bg-gray-700/50"
      data-testid="auth-override-status"
      role="status">
      <OIcon
        collection="heroicons"
        :name="effectiveEnabled ? 'check-circle' : 'minus-circle'"
        :class="[
          'size-5 flex-shrink-0',
          effectiveEnabled
            ? 'text-green-500 dark:text-green-400'
            : 'text-gray-400 dark:text-gray-500',
        ]"
        aria-hidden="true" />
      <p class="flex-1 text-sm text-gray-700 dark:text-gray-300">
        {{ statusLabel }}:
        <span class="font-semibold text-gray-900 dark:text-white">
          {{ effectiveEnabled ? t('web.COMMON.enabled') : t('web.COMMON.disabled') }}
        </span>
      </p>
      <span
        v-if="workspaceDefault"
        data-testid="workspace-default-badge"
        class="inline-flex items-center rounded-full bg-blue-50 px-2.5 py-0.5 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-200 dark:bg-blue-900/20 dark:text-blue-300 dark:ring-blue-800">
        {{ t('web.domains.auth_override.workspace_default_badge') }}
      </span>
    </div>

    <!-- Dormant warning: global kill switch is off -->
    <div
      v-if="globalEnabled === false"
      data-testid="auth-override-dormant-warning"
      role="status"
      aria-live="polite"
      class="flex items-start gap-3 rounded-md bg-yellow-50 px-4 py-3 dark:bg-yellow-900/20">
      <OIcon
        collection="heroicons"
        name="exclamation-triangle"
        class="mt-0.5 size-5 flex-shrink-0 text-yellow-500 dark:text-yellow-400"
        aria-hidden="true" />
      <p class="flex-1 text-sm text-yellow-700 dark:text-yellow-300">
        {{ dormantNotice }}
      </p>
    </div>
  </div>
</template>
