<!-- src/apps/session/views/CheckEmail.vue -->

<script setup lang="ts">
  import AuthView from '@/apps/session/components/AuthView.vue';
  import ResendVerificationForm from '@/apps/session/components/ResendVerificationForm.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { CHECK_EMAIL_STATE_KEY } from '@/shared/constants/checkEmail';
  import { sanitizeDisplayEmail } from '@/utils/pii';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRoute, useRouter } from 'vue-router';

  /**
   * Post-signup "Check your email" confirmation page.
   *
   * Reached via useAuth.signup() after an account is created but before it is
   * verified. It is a single-purpose, low-anxiety screen: confirm the email is
   * on its way, echo the address it went to (so a typo is obvious), and give
   * exactly two recovery paths — resend, or start over with a different address.
   *
   * Deliberately minimal: the real next step is the link already in the user's
   * inbox, so there is no primary button competing with it, and no brand icon
   * distracting from it. The address is shown as static text, not an editable
   * field — correcting a typo is what "start over" is for, and an inline edit
   * would fork the flow and muddy the resend-vs-signup intent.
   *
   * The email arrives via router history state (not the URL): it is PII, and a
   * query string would leak it through history, the Referer header, access logs
   * and Sentry (see src/utils/pii.ts and src/router/README.md). It is therefore
   * absent on a manual refresh or a shared link — we degrade to the generic
   * copy, which is the correct fallback. Billing/redirect params are non-PII and
   * ride in the query, so they are preserved on the "start over" link.
   */

  const { t } = useI18n();
  const route = useRoute();
  const router = useRouter();

  const email = computed(() => {
    const state = router.options.history.state as Record<string, unknown> | null;
    return sanitizeDisplayEmail(state?.[CHECK_EMAIL_STATE_KEY]);
  });

  // Preserve billing + redirect params on the "start over" link so the pending
  // checkout / invitation flow continues once the user signs up again. The email
  // is intentionally NOT forwarded: "start over" exists to correct a wrong
  // address, so re-prefilling the mistyped one would be counterproductive — and
  // would put PII back into a URL.
  function linkWith(path: string): string | { path: string; query: Record<string, string> } {
    const query: Record<string, string> = {};
    for (const param of ['redirect', 'product', 'interval']) {
      if (typeof route.query[param] === 'string') {
        query[param] = route.query[param] as string;
      }
    }
    return Object.keys(query).length > 0 ? { path, query } : path;
  }

  const signupLink = computed(() => linkWith('/signup'));
</script>

<template>
  <AuthView
    :heading="t('web.auth.check_email.title')"
    heading-id="check-email-heading"
    :with-heading="true"
    :with-subheading="false"
    :omit-icon="true"
    :hide-background-icon="true">
    <template #form>
      <div
        class="space-y-6"
        data-testid="check-email-view">
        <!-- Envelope icon: the page's focal point -->
        <div class="flex justify-center">
          <div class="rounded-full bg-brand-100 p-4 dark:bg-brand-900/30">
            <svg
              class="size-10 text-brand-600 dark:text-brand-400"
              fill="none"
              stroke="currentColor"
              stroke-width="1.5"
              viewBox="0 0 24 24"
              aria-hidden="true">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M21.75 6.75v10.5a2.25 2.25 0 0 1-2.25 2.25h-15a2.25 2.25 0 0 1-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0 0 19.5 4.5h-15a2.25 2.25 0 0 0-2.25 2.25m19.5 0v.243a2.25 2.25 0 0 1-1.07 1.916l-7.5 4.615a2.25 2.25 0 0 1-2.36 0L3.32 8.91a2.25 2.25 0 0 1-1.07-1.916V6.75" />
            </svg>
          </div>
        </div>

        <!-- The one thing to do: check this inbox. The address is the message;
             a help icon carries the details (what was sent, what to do next) so
             the screen stays a single, clear instruction rather than a wall of
             text the email itself already repeats. -->
        <div class="text-center">
          <div
            v-if="email"
            class="flex items-center justify-center gap-1.5">
            <span
              class="text-lg font-semibold break-all text-gray-900 dark:text-white"
              data-testid="check-email-address">
              {{ email }}
            </span>
            <span
              class="shrink-0 cursor-help text-gray-400 dark:text-gray-500"
              role="img"
              :aria-label="t('web.auth.check_email.help')"
              :title="t('web.auth.check_email.help')"
              data-testid="check-email-help">
              <OIcon
                collection="heroicons"
                name="question-mark-circle"
                size="5"
                aria-hidden="true" />
            </span>
          </div>
          <p
            v-else
            class="text-sm text-gray-600 dark:text-gray-400">
            {{ t('web.auth.check_email.sent_to_generic') }}
          </p>
        </div>

        <!-- Recovery paths, deliberately de-emphasised: one-click resend and a
             spam nudge. The "wrong address" escape lives in the footer. -->
        <div class="space-y-2">
          <ResendVerificationForm
            :email="email"
            :compact="!!email" />
          <p class="text-center text-xs text-gray-500 dark:text-gray-400">
            {{ t('web.auth.check_email.spam_hint') }}
          </p>
        </div>
      </div>
    </template>

    <!-- Wrong-address escape: correcting a typo means starting over, not an
         inline edit of the address. -->
    <template #footer>
      <span class="text-gray-600 dark:text-gray-400">
        {{ t('web.auth.check_email.wrong_email') }}
      </span>
      {{ ' ' }}
      <router-link
        :to="signupLink"
        class="font-medium text-brand-600 underline transition-colors duration-200 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300"
        data-testid="check-email-start-over-link">
        {{ t('web.auth.check_email.start_over') }}
      </router-link>
    </template>
  </AuthView>
</template>
