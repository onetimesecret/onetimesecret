<!-- src/shared/components/ui/ImpersonationBanner.vue -->

<script setup lang="ts">
  import {
    IMPERSONATION_STOP_FALLBACK_PATH,
    stopImpersonation,
  } from '@/services/impersonation.service';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { hardNavigate } from '@/utils/navigation';
  import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * The standing notice that this session is a colonel presenting as another
   * customer, and the control that ends it.
   *
   * This is a SAFETY CONTROL, not decoration. It is mounted in App.vue above
   * the layout so it appears on every route of both bundles, and it renders
   * only from `bootstrapStore.impersonation` — the block the server re-derives
   * per request from the session marker. It therefore cannot claim an
   * impersonation the server is not actually serving, and it disappears by
   * itself once the marker is stopped or expires and the payload is re-read.
   *
   * The countdown is local arithmetic against the server's `expires_at`, so it
   * is an ESTIMATE of a server-side deadline, never the deadline itself: the
   * middleware ends the session on its own clock whether or not this component
   * is mounted. Reaching 0:00 is not made to log anyone out from here — the
   * next request does that — because a client-side timer firing a navigation
   * would fight the server for authority over when the session ended.
   */

  const { t } = useI18n();
  const bootstrapStore = useBootstrapStore();

  const impersonation = computed(() => bootstrapStore.impersonation);

  // ---- Countdown ------------------------------------------------------------

  const now = ref(Date.now());
  let ticker: ReturnType<typeof setInterval> | undefined;

  onMounted(() => {
    ticker = setInterval(() => {
      now.value = Date.now();
    }, 1000);
  });

  // Cleared on unmount so a route change (or a stop that leaves the banner
  // mounted while the document navigates) cannot leave a timer writing to a
  // disposed component.
  onBeforeUnmount(() => {
    if (ticker !== undefined) clearInterval(ticker);
    ticker = undefined;
  });

  /** Whole seconds left, floored at 0 — never negative, never NaN. */
  const secondsRemaining = computed(() => {
    const expiresAt = impersonation.value?.expires_at;
    if (typeof expiresAt !== 'number' || !Number.isFinite(expiresAt)) return 0;
    return Math.max(0, Math.floor((expiresAt * 1000 - now.value) / 1000));
  });

  /** m:ss (or h:mm:ss past an hour, which the 30-minute TTL never reaches). */
  const countdown = computed(() => {
    const total = secondsRemaining.value;
    const minutes = Math.floor(total / 60);
    const seconds = total % 60;
    return `${minutes}:${String(seconds).padStart(2, '0')}`;
  });

  const expired = computed(() => secondsRemaining.value === 0);

  // ---- Stop -----------------------------------------------------------------

  const stopping = ref(false);
  const stopFailed = ref(false);

  async function handleStop(): Promise<void> {
    if (stopping.value) return;
    stopping.value = true;
    stopFailed.value = false;

    try {
      const redirect = await stopImpersonation();
      // Hard navigation: the console is a separate bundle and the identity in
      // the document is now stale. `stopping` is deliberately left true — the
      // document is on its way out and re-enabling the button would invite a
      // second stop against a session that no longer has a marker.
      hardNavigate(redirect, IMPERSONATION_STOP_FALLBACK_PATH);
    } catch {
      // Reaching here means the session was NOT ended: the service already
      // absorbs the two "you are no longer impersonating" outcomes (2xx, and
      // 404 = no marker to stop) and resolves them to a path. So the marker is
      // presumed STILL ACTIVE — say so and let them retry rather than
      // navigating away from a session that is still live.
      stopFailed.value = true;
      stopping.value = false;
    }
  }
</script>

<template>
  <div
    v-if="impersonation"
    role="status"
    data-testid="impersonation-banner"
    class="border-b-2 border-amber-500 bg-amber-100 px-4 py-2 text-amber-900 dark:border-amber-400 dark:bg-amber-950 dark:text-amber-100">
    <div class="container mx-auto flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
      <div class="flex min-w-0 items-center gap-3">
        <OIcon
          collection="heroicons"
          name="eye"
          class="size-5 shrink-0 text-amber-700 dark:text-amber-300"
          aria-hidden="true" />
        <div class="min-w-0 text-sm">
          <p class="font-semibold">
            {{ t('web.impersonation.banner.label') }}
          </p>
          <p class="truncate">
            <span data-testid="impersonation-target">{{
              t('web.impersonation.banner.viewingAs', { email: impersonation.target_email })
            }}</span>
            <span
              class="mx-1"
              aria-hidden="true"
              >·</span
            >
            <span>{{ t('web.impersonation.banner.readOnly') }}</span>
          </p>
        </div>
      </div>

      <div class="flex shrink-0 items-center gap-3">
        <!-- aria-live="off": the ticking value must not be re-announced every
             second inside the role="status" region. -->
        <span
          aria-live="off"
          data-testid="impersonation-countdown"
          :data-remaining="countdown"
          class="font-mono text-sm tabular-nums"
          :class="expired ? 'font-bold text-red-700 dark:text-red-300' : ''">
          {{ t('web.impersonation.banner.expiresIn', { time: countdown }) }}
        </span>
        <button
          type="button"
          data-testid="impersonation-stop"
          :disabled="stopping"
          class="inline-flex items-center gap-2 rounded-md border border-amber-700 px-3 py-1 text-sm font-semibold text-amber-900 transition-colors hover:bg-amber-200 focus:ring-2 focus:ring-amber-600 focus:ring-offset-1 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-amber-300 dark:text-amber-100 dark:hover:bg-amber-900/60 dark:focus:ring-amber-300"
          @click="handleStop">
          {{
            stopping ? t('web.impersonation.banner.stopping') : t('web.impersonation.banner.stop')
          }}
        </button>
      </div>
    </div>

    <p
      v-if="stopFailed"
      role="alert"
      data-testid="impersonation-stop-error"
      class="container mx-auto mt-1 text-sm font-medium text-red-700 dark:text-red-300">
      {{ t('web.impersonation.banner.stopFailed') }}
    </p>
  </div>
</template>
