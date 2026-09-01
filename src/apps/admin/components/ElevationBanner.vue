<!-- src/apps/admin/components/ElevationBanner.vue -->

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { computed, onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';

  import { useColonelElevation } from '../composables/useColonelElevation';

  /**
   * A live step-up (sudo) window, shown while one is open (#4327).
   *
   * Mounted once in AdminLayout. Renders NOTHING when elevation is disabled by
   * config or when no window is live — the console's ordinary state is
   * unelevated, and a permanent "you are not elevated" bar would train operators
   * to ignore the bar that matters.
   *
   * The countdown is driven entirely by {@link useColonelElevation}'s local
   * timer: this component issues NO HTTP of its own, ever, and the composable's
   * doc block explains why that is a shipped security property rather than a
   * style choice (a poll would re-stamp last_activity_at and make #4331's idle
   * timeout unreachable while an admin tab is open).
   *
   * A window minted with `recent_auth` is labelled DIFFERENTLY: that path
   * elevates without a credential, so it must be visible while it is live rather
   * than indistinguishable from a password step-up.
   */
  const { t } = useI18n();

  const elevation = useColonelElevation();

  // The one status fetch the console makes on entry. Everything after this is
  // triggered by an operator action or a 403.
  onMounted(() => {
    void elevation.refresh();
  });

  const visible = computed(() => elevation.enabled.value && elevation.elevated.value);

  const viaRecentAuth = computed(() => elevation.activeFactor.value === 'recent_auth');

  /** mm:ss, computed locally from the expiry — no request per tick. */
  const remaining = computed(() => {
    const total = Math.max(0, elevation.secondsRemaining.value);
    const minutes = Math.floor(total / 60);
    const seconds = total % 60;
    return `${minutes}:${String(seconds).padStart(2, '0')}`;
  });
</script>

<template>
  <div
    v-if="visible"
    class="flex items-center justify-between gap-3 border-b px-5 py-2 text-sm sm:px-8"
    :class="
      viaRecentAuth
        ? 'border-amber-300 bg-amber-50 text-amber-900 dark:border-amber-700 dark:bg-amber-950/50 dark:text-amber-200'
        : 'border-brand-200 bg-brand-50 text-brand-900 dark:border-brand-800 dark:bg-brand-950/50 dark:text-brand-200'
    "
    data-testid="elevation-banner">
    <span class="flex min-w-0 items-center gap-2">
      <OIcon
        collection="heroicons"
        :name="viaRecentAuth ? 'exclamation-triangle' : 'lock-open'"
        size="4"
        aria-hidden="true" />
      <span class="truncate">
        {{
          viaRecentAuth
            ? t('web.admin.elevation.banner.activeRecentAuth', { remaining })
            : t('web.admin.elevation.banner.active', { remaining })
        }}
      </span>
    </span>

    <button
      type="button"
      class="shrink-0 rounded px-2 py-1 font-semibold underline underline-offset-2 hover:bg-black/5 disabled:opacity-50 dark:hover:bg-white/10"
      :disabled="elevation.loading.value"
      data-testid="elevation-drop"
      @click="elevation.drop()">
      {{ t('web.admin.elevation.banner.drop') }}
    </button>
  </div>
</template>
