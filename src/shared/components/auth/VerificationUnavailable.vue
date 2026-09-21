<!-- src/shared/components/auth/VerificationUnavailable.vue -->

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useAuthStore } from '@/shared/stores/authStore';
  import { nextTick, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Shown INSTEAD of a protected route's content while the session cannot be
   * verified (#4460): status `unavailable`, or a `checking` that was never
   * resolved.
   *
   * This is not a sign-out. The server session is untouched and the last
   * accepted snapshot is still held; what is withheld is the protected UI,
   * because authority cannot be established (fail-safe defaults). The refresh
   * coordinator keeps retrying on backoff, and the first successful refresh
   * applies whatever the server reports, which swaps this view back out
   * without a page load. The button only skips the backoff wait.
   */

  const { t } = useI18n();
  const authStore = useAuthStore();

  const retrying = ref(false);
  const retryFailed = ref(false);
  const heading = ref<HTMLElement | null>(null);

  // The route content was replaced by this view: move focus to it so keyboard
  // and screen-reader users are not left on a node that no longer exists.
  onMounted(() => nextTick(() => heading.value?.focus()));

  async function retry(): Promise<void> {
    if (retrying.value) return;
    retrying.value = true;
    retryFailed.value = false;
    try {
      const outcome = await authStore.retryNow();
      // PR #4497 item 11: `allocation-unavailable` is a bounded coordinator
      // retry scheduled elsewhere; from the user's perspective the retry did
      // not land, so surface the same "please try again" state as `failed`.
      retryFailed.value = outcome === 'failed' || outcome === 'allocation-unavailable';
    } finally {
      retrying.value = false;
    }
  }
</script>

<template>
  <section
    data-testid="verification-unavailable"
    aria-labelledby="verification-unavailable-title"
    class="mx-auto my-16 max-w-xl px-4 text-center">
    <OIcon
      collection="heroicons"
      name="arrow-path"
      class="mx-auto size-10 text-gray-400 dark:text-gray-500"
      aria-hidden="true" />
    <h1
      id="verification-unavailable-title"
      ref="heading"
      tabindex="-1"
      class="mt-4 text-xl font-semibold text-gray-900 focus:outline-none dark:text-gray-100">
      {{ t('web.auth.session.verification_unavailable_title') }}
    </h1>
    <p class="mt-2 text-base text-gray-600 dark:text-gray-300">
      {{ t('web.auth.session.verification_unavailable_body') }}
    </p>

    <button
      type="button"
      data-testid="verification-retry"
      :disabled="retrying"
      :aria-busy="retrying"
      class="mt-6 inline-flex items-center gap-2 rounded-md bg-brand-600 px-4 py-2 text-sm font-semibold text-white transition-colors hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none disabled:cursor-not-allowed disabled:opacity-60 dark:focus:ring-offset-gray-900"
      @click="retry">
      {{ retrying ? t('web.auth.session.retrying') : t('web.auth.session.retry') }}
    </button>

    <p
      v-if="retryFailed"
      role="status"
      data-testid="verification-retry-failed"
      class="mt-3 text-sm text-gray-600 dark:text-gray-300">
      {{ t('web.auth.session.retry_failed') }}
    </p>
  </section>
</template>
