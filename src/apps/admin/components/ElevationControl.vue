<!-- src/apps/admin/components/ElevationControl.vue -->

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  import { useColonelElevation } from '../composables/useColonelElevation';
  import { formatElevationCountdown } from '../utils/elevationCountdown';

  /**
   * The step-up (sudo) state in the console header (#4327), beside the
   * operator's email and the theme toggle.
   *
   * - No window live: an "Elevate" button that opens the shared prompt, so the
   *   operator can opt in before starting a destructive task instead of being
   *   asked mid-action.
   * - A window live: the unlocked icon and the m:ss left. Clicking it drops the
   *   window, the same as the banner's "Drop elevation".
   * - Hidden when step-up is disabled by config, and while the admin session
   *   itself has expired (#4331): the banner owns that state, and no window
   *   means anything then.
   *
   * Issues no HTTP of its own on mount or per tick. The m:ss reads the
   * composable's local countdown; requests happen only on a click (elevate via
   * the prompt, or drop). See useColonelElevation for why no timer under
   * src/apps/admin may make a request.
   */
  const { t } = useI18n();

  const elevation = useColonelElevation();

  const visible = computed(() => elevation.enabled.value && !elevation.adminSessionExpired.value);

  const viaRecentAuth = computed(() => elevation.activeFactor.value === 'recent_auth');

  const remaining = computed(() => formatElevationCountdown(elevation.secondsRemaining.value));

  const dropLabel = computed(() =>
    t('web.admin.elevation.control.drop', { remaining: remaining.value })
  );

  function onElevate(): void {
    // Nothing waits on the answer: the operator opted in ahead of any action.
    void elevation.ensureElevated();
  }

  function onDrop(): void {
    void elevation.drop();
  }
</script>

<template>
  <button
    v-if="visible && elevation.elevated.value"
    type="button"
    class="inline-flex h-9 items-center gap-1.5 rounded-md border px-2.5 text-sm font-medium tabular-nums transition-colors focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:opacity-50"
    :class="
      viaRecentAuth
        ? 'border-amber-300 bg-amber-50 text-amber-900 hover:bg-amber-100 dark:border-amber-700 dark:bg-amber-950/50 dark:text-amber-200 dark:hover:bg-amber-900/50'
        : 'border-brand-200 bg-brand-50 text-brand-900 hover:bg-brand-100 dark:border-brand-800 dark:bg-brand-950/50 dark:text-brand-200 dark:hover:bg-brand-900/50'
    "
    :aria-label="dropLabel"
    :title="dropLabel"
    :disabled="elevation.loading.value"
    data-testid="elevation-control-drop"
    @click="onDrop">
    <OIcon
      collection="heroicons"
      name="lock-open"
      size="4"
      aria-hidden="true" />
    <span data-testid="elevation-control-remaining">{{ remaining }}</span>
  </button>

  <button
    v-else-if="visible"
    type="button"
    class="inline-flex h-9 items-center gap-1.5 rounded-md border border-gray-300 px-2.5 text-sm font-medium text-gray-700 transition-colors hover:bg-gray-100 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:opacity-50 dark:border-gray-700 dark:text-gray-300 dark:hover:bg-gray-800"
    :title="t('web.admin.elevation.control.elevateHint')"
    :disabled="elevation.promptOpen.value"
    data-testid="elevation-control-elevate"
    @click="onElevate">
    <OIcon
      collection="heroicons"
      name="lock-closed"
      size="4"
      aria-hidden="true" />
    <span>{{ t('web.admin.elevation.control.elevate') }}</span>
  </button>
</template>
