<!-- src/shared/components/auth/StaleSessionNotice.vue -->

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useAuthStore } from '@/shared/stores/authStore';
  import { onUnmounted, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * The persistent notice of the stale-session state (ADR-046 "Forced page
   * load", #4465).
   *
   * The refresh coordinator enters that state synchronously BEFORE it calls
   * `window.location.reload()`. If the reload proceeds, the page and this
   * notice are discarded together. It stays on screen in two cases: the user
   * cancelled the browser's `beforeunload` prompt (browsers do not report
   * that, which is why the state is entered first), or a second forced page
   * load was demanded within a minute and the loop bound refused it.
   *
   * The page content is deliberately left in place underneath: the user can
   * copy unsubmitted input and reload when ready. The client never retries the
   * reload itself, and no snapshot is applied while the state holds, so the
   * only way out is the button below (or any other page load).
   *
   * Mounted in App.vue above the layout so it appears on every route of both
   * bundles, like ImpersonationBanner.
   */

  const { t } = useI18n();
  const authStore = useAuthStore();

  // A user-initiated reload: not bounded, and the browser still prompts if a
  // view holds unsubmitted input.
  const reload = () => window.location.reload();

  // A page that sticks its own bar to the viewport top (the domain pages'
  // headers) has to sit below this notice instead of under it. The notice
  // wraps on narrow screens, so publish its measured height on the root
  // element as --stale-session-notice-height. The property is absent while
  // the notice is not shown; consumers fall back to 0px.
  const HEIGHT_PROPERTY = '--stale-session-notice-height';
  const noticeEl = ref<HTMLElement | null>(null);
  let resizeObserver: ResizeObserver | null = null;

  const publishHeight = () => {
    const el = noticeEl.value;
    if (el) {
      document.documentElement.style.setProperty(HEIGHT_PROPERTY, `${el.offsetHeight}px`);
    } else {
      document.documentElement.style.removeProperty(HEIGHT_PROPERTY);
    }
  };

  const stopMeasuring = () => {
    resizeObserver?.disconnect();
    resizeObserver = null;
    window.removeEventListener('resize', publishHeight);
  };

  // The element exists only while the state holds (v-if), so follow the ref.
  watch(
    noticeEl,
    (el) => {
      stopMeasuring();
      publishHeight();
      if (!el) return;
      if (typeof ResizeObserver !== 'undefined') {
        resizeObserver = new ResizeObserver(publishHeight);
        resizeObserver.observe(el);
      } else {
        window.addEventListener('resize', publishHeight);
      }
    },
    { flush: 'post' }
  );

  onUnmounted(() => {
    stopMeasuring();
    document.documentElement.style.removeProperty(HEIGHT_PROPERTY);
  });
</script>

<template>
  <div
    v-if="authStore.staleSession"
    ref="noticeEl"
    role="alert"
    data-testid="stale-session-notice"
    class="sticky top-0 z-50 border-b-2 border-amber-500 bg-amber-100 px-4 py-2 text-amber-900 dark:border-amber-400 dark:bg-amber-950 dark:text-amber-100">
    <div class="container mx-auto flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
      <div class="flex min-w-0 items-start gap-3">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          class="mt-0.5 size-5 shrink-0 text-amber-700 dark:text-amber-300"
          aria-hidden="true" />
        <div class="min-w-0 text-sm">
          <p class="font-semibold">
            {{ t('web.auth.session.stale_session_title') }}
          </p>
          <p>{{ t('web.auth.session.stale_session_notice') }}</p>
        </div>
      </div>

      <button
        type="button"
        data-testid="stale-session-reload"
        class="inline-flex shrink-0 items-center gap-2 rounded-md border border-amber-700 px-3 py-1 text-sm font-semibold text-amber-900 transition-colors hover:bg-amber-200 focus:ring-2 focus:ring-amber-600 focus:ring-offset-1 focus:outline-none dark:border-amber-300 dark:text-amber-100 dark:hover:bg-amber-900/60 dark:focus:ring-amber-300"
        @click="reload">
        {{ t('web.auth.session.reload_now') }}
      </button>
    </div>
  </div>
</template>
