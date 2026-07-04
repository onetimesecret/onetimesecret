<!-- src/apps/session/components/ResendVerificationForm.vue -->

<script setup lang="ts">
  import { useAuth } from '@/shared/composables/useAuth';
  import { ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Self-service "resend verification email" form.
   *
   * Used by the verify-account screen for accounts that are stuck Unverified and
   * whose verification link was lost or expired. The flow is unauthenticated:
   * such an account cannot log in, so the user has no session and supplies their
   * email directly.
   *
   * Anti-enumeration: on a successful (accepted) request we always render the
   * same neutral confirmation, regardless of whether the email maps to an
   * existing/verified/unverified account — mirroring the backend's uniform
   * `{ sent: true }` response. The confirmation is shown ONLY when the request
   * was accepted; a genuine transport/validation failure (network, 5xx, blank
   * input) keeps the form visible with a retryable error. Those failure cases
   * are not account-state-dependent, so they leak nothing.
   */

  export interface Props {
    /**
     * Optional address to prefill the input with. Passed by the post-signup
     * "Check your email" page, where the email is already known — the user can
     * hit resend without retyping it. Defaults to empty for the verify-account
     * recovery flow, where no email is known up front.
     */
    email?: string;
    /**
     * Compact mode: render a single one-click "Resend email" button and nothing
     * else (no help text, no email input, no surrounding panel). Used on the
     * post-signup "Check your email" page, where the address is already known,
     * so the editable input would only compete with the "Start over" recovery
     * path. The verify-account recovery flow leaves this false and shows the
     * full form, since no email is known there.
     */
    compact?: boolean;
  }

  const props = withDefaults(defineProps<Props>(), {
    email: '',
    compact: false,
  });

  const { t } = useI18n();
  const { resendVerificationEmail, isLoading } = useAuth();

  const email = ref(props.email);
  const submitted = ref(false);
  const failed = ref(false);

  async function onResend() {
    if (!email.value) return;
    failed.value = false;

    const accepted = await resendVerificationEmail(email.value);
    if (accepted) {
      submitted.value = true;
    } else {
      // Network / 5xx / malformed request. Keep the form so the user can retry.
      failed.value = true;
    }
  }
</script>

<template>
  <div
    :class="compact ? 'space-y-2' : 'space-y-3 rounded-md bg-gray-50 p-4 dark:bg-gray-800/50'"
    data-testid="resend-verification-form">
    <!-- Help text + editable input: only the full (non-compact) form needs them.
         Compact mode already knows the address, so it shows a bare button. -->
    <p
      v-if="!compact"
      class="text-sm text-gray-600 dark:text-gray-300">
      {{ t('web.auth.verify.resend_help_text') }}
    </p>

    <!-- Request form: a <form> so Enter submits and type=email gets native validation. -->
    <form
      v-if="!submitted"
      class="space-y-3"
      @submit.prevent="onResend">
      <template v-if="!compact">
        <label
          for="resend-verification-email"
          class="sr-only">
          {{ t('web.COMMON.email_address') }}
        </label>
        <input
          id="resend-verification-email"
          v-model="email"
          type="email"
          name="resendEmail"
          autocomplete="email"
          :disabled="isLoading"
          :placeholder="t('web.COMMON.email_placeholder')"
          class="block w-full appearance-none rounded-md border border-gray-300 px-3 py-2 text-gray-900 placeholder:text-gray-500 focus:border-brand-500 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400"
          data-testid="resend-verification-email-input" />
      </template>

      <!-- Compact mode de-emphasises resend (secondary/outline): the real next
           step is clicking the link already in the user's inbox. -->
      <button
        v-if="compact"
        type="submit"
        :disabled="isLoading || !email"
        class="inline-flex w-full justify-center rounded-md border border-gray-300 bg-white px-4 py-2 font-medium text-gray-900 shadow-sm transition hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-800 dark:text-white dark:hover:bg-gray-700"
        data-testid="resend-verification-email-submit">
        {{ t('web.auth.verify.resend_short') }}
      </button>
      <button
        v-else
        type="submit"
        :disabled="isLoading || !email"
        class="inline-flex w-full justify-center rounded-md bg-brand-600 px-4 py-2 font-medium text-white shadow-sm transition duration-300 hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-600 dark:hover:bg-brand-700"
        data-testid="resend-verification-email-submit">
        {{ t('web.auth.verify.resend_button') }}
      </button>

      <p
        v-if="failed"
        class="text-sm text-red-600 dark:text-red-400"
        role="alert"
        data-testid="resend-verification-email-error">
        {{ t('web.auth.verify.resend_error') }}
      </p>
    </form>

    <!-- Neutral confirmation, shown for every accepted request (anti-enumeration). -->
    <p
      v-else
      class="text-sm text-green-700 dark:text-green-300"
      :class="{ 'text-center': compact }"
      data-testid="resend-verification-email-confirmation">
      {{ t('web.auth.verify.resend_sent') }}
    </p>
  </div>
</template>
