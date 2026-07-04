<!-- src/apps/session/views/CheckEmail.vue -->

<script setup lang="ts">
  import AuthView from '@/apps/session/components/AuthView.vue';
  import ResendVerificationForm from '@/apps/session/components/ResendVerificationForm.vue';
  import { computed } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRoute } from 'vue-router';

  /**
   * Post-signup "Check your email" confirmation page.
   *
   * Reached via useAuth.signup() after an account is created but before it is
   * verified. It is a single-purpose, low-anxiety screen: confirm the email is
   * on its way, echo the address it went to (so a typo is obvious), and give
   * exactly two recovery paths — resend, or start over with a different address.
   *
   * Deliberately minimal: the real next step is the link already in the user's
   * inbox, so there is no primary button competing with it. The address is shown
   * as static text, not an editable field — correcting a typo is what "start
   * over" is for, and an inline edit would fork the flow and muddy the
   * resend-vs-signup intent.
   *
   * The email arrives as a query param (?email=...). Billing/redirect params are
   * preserved on the onward links so the checkout flow survives the detour.
   */

  const { t } = useI18n();
  const route = useRoute();

  const email = computed(() => (typeof route.query.email === 'string' ? route.query.email : ''));

  // Preserve email + billing + redirect params on the onward links so the
  // pending checkout / invitation flow continues once the user signs in.
  function linkWith(path: string): string | { path: string; query: Record<string, string> } {
    const query: Record<string, string> = {};
    for (const param of ['email', 'redirect', 'product', 'interval']) {
      if (typeof route.query[param] === 'string') {
        query[param] = route.query[param] as string;
      }
    }
    return Object.keys(query).length > 0 ? { path, query } : path;
  }

  const signinLink = computed(() => linkWith('/signin'));
  const signupLink = computed(() => linkWith('/signup'));
</script>

<template>
  <AuthView
    :heading="t('web.auth.check_email.title')"
    heading-id="check-email-heading"
    :with-heading="true"
    :with-subheading="false"
    :hide-icon="false"
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

        <!-- Where the link went + the one thing to do next -->
        <div class="space-y-2 text-center">
          <template v-if="email">
            <p class="text-sm text-gray-600 dark:text-gray-400">
              {{ t('web.auth.check_email.sent_to') }}
            </p>
            <p
              class="text-lg font-semibold break-all text-gray-900 dark:text-white"
              data-testid="check-email-address">
              {{ email }}
            </p>
          </template>
          <p
            v-else
            class="text-sm text-gray-600 dark:text-gray-400">
            {{ t('web.auth.check_email.sent_to_generic') }}
          </p>
          <p class="pt-1 text-sm text-gray-700 dark:text-gray-300">
            {{ t('web.auth.check_email.instructions') }}
          </p>
        </div>

        <!-- Recovery paths, deliberately de-emphasised: one-click resend, then a
             spam nudge and a "start over" escape for a wrong address. -->
        <div class="space-y-2">
          <ResendVerificationForm
            :email="email"
            :compact="!!email" />
          <p class="text-center text-xs text-gray-500 dark:text-gray-400">
            {{ t('web.auth.check_email.spam_hint') }}
          </p>
          <p class="text-center text-xs text-gray-500 dark:text-gray-400">
            {{ t('web.auth.check_email.wrong_email') }}
            {{ ' ' }}
            <router-link
              :to="signupLink"
              class="font-medium text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300"
              data-testid="check-email-start-over-link">
              {{ t('web.auth.check_email.start_over') }}
            </router-link>
          </p>
        </div>
      </div>
    </template>

    <!-- Escape hatch for anyone who has already verified (e.g. in another tab). -->
    <template #footer>
      <span class="text-gray-600 dark:text-gray-400">
        {{ t('web.auth.check_email.already_verified') }}
      </span>
      {{ ' ' }}
      <router-link
        :to="signinLink"
        class="font-medium text-brand-600 underline transition-colors duration-200 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300"
        data-testid="check-email-signin-link">
        {{ t('web.auth.check_email.signin_link') }}
      </router-link>
    </template>
  </AuthView>
</template>
