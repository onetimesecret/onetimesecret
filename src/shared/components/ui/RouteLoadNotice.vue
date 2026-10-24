<!-- src/shared/components/ui/RouteLoadNotice.vue -->

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { dismissRouteLoadFailure, routeLoadFailure } from '@/utils/routeLoadFailure';
  import { useI18n } from 'vue-i18n';

  /**
   * The notice for a page that could not open because its chunk failed to
   * load while this page declined to reload itself (src/utils/preloadError.ts:
   * a one-time value on screen, or the ADR-046 bound spent). Without it the
   * clicked link does nothing visible.
   *
   * Inline and persistent, like StaleSessionNotice: the page content stays
   * underneath so the user can copy what they still need, and the button is a
   * user-initiated reload, not bounded. Mounted in App.vue above the layout so
   * it appears on every route of both bundles. Cleared by the next navigation
   * that completes (src/utils/routeLoadFailure.ts) or by its dismiss button.
   */

  const { t } = useI18n();

  // A user-initiated reload: not bounded, and the browser still prompts if a
  // view holds unsubmitted input.
  const reload = () => window.location.reload();
</script>

<template>
  <div
    v-if="routeLoadFailure"
    role="alert"
    data-testid="route-load-notice"
    :class="[
      'border-b-2 border-amber-500 bg-amber-100 px-4 py-2 text-amber-900',
      'dark:border-amber-400 dark:bg-amber-950 dark:text-amber-100',
    ]">
    <div class="container mx-auto flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
      <div class="flex min-w-0 items-start gap-3">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          class="mt-0.5 size-5 shrink-0 text-amber-700 dark:text-amber-300"
          aria-hidden="true" />
        <div class="min-w-0 text-sm">
          <p class="font-semibold">{{ t('web.layout.route_load_failed.title') }}</p>
          <p>{{ t('web.layout.route_load_failed.body') }}</p>
        </div>
      </div>

      <div class="flex shrink-0 items-center gap-2">
        <button
          type="button"
          data-testid="route-load-notice-reload"
          :class="[
            'inline-flex items-center rounded-md border border-amber-700 px-3 py-1 text-sm font-semibold',
            'text-amber-900 transition-colors hover:bg-amber-200',
            'focus:ring-2 focus:ring-amber-600 focus:ring-offset-1 focus:outline-none',
            'dark:border-amber-300 dark:text-amber-100 dark:hover:bg-amber-900/60 dark:focus:ring-amber-300',
          ]"
          @click="reload">
          {{ t('web.layout.route_load_failed.reload') }}
        </button>
        <button
          type="button"
          data-testid="route-load-notice-dismiss"
          :aria-label="t('web.layout.route_load_failed.dismiss')"
          :class="[
            'rounded-md p-1 text-amber-800 transition-colors hover:bg-amber-200',
            'focus:ring-2 focus:ring-amber-600 focus:outline-none',
            'dark:text-amber-200 dark:hover:bg-amber-900/60 dark:focus:ring-amber-300',
          ]"
          @click="dismissRouteLoadFailure">
          <OIcon
            collection="heroicons"
            name="x-mark"
            class="size-5"
            aria-hidden="true" />
        </button>
      </div>
    </div>
  </div>
</template>
