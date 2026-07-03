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
   * verified. Unlike the transient success toast, this page persistently:
   *   - echoes the address the verification link was sent to (so a typo is
   *     obvious immediately),
   *   - explains the next step (click the link, then sign in), and
   *   - offers a self-service resend, prefilled with the same address.
   *
   * The email arrives as a query param (?email=...). Billing/redirect params
   * are preserved on the onward links so the checkout flow survives the detour.
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
        <!-- Envelope icon reinforces the "we sent you mail" message -->
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

        <!-- Address the verification link was sent to -->
        <div class="space-y-1 text-center">
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
        </div>

        <!-- Next step + spam hint -->
        <div class="space-y-2 text-center">
          <p class="text-sm text-gray-700 dark:text-gray-300">
            {{ t('web.auth.check_email.instructions') }}
          </p>
          <p class="text-xs text-gray-500 dark:text-gray-400">
            {{ t('web.auth.check_email.spam_hint') }}
          </p>
        </div>

        <!-- Self-service resend, prefilled with the known address -->
        <ResendVerificationForm :email="email" />

        <!-- Onward action: sign in (usable once verified) -->
        <div class="text-center">
          <router-link
            :to="signinLink"
            class="inline-flex w-full justify-center rounded-md border border-gray-300 bg-white px-4 py-2 font-medium text-gray-900 shadow-sm transition hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none dark:border-gray-600 dark:bg-gray-800 dark:text-white dark:hover:bg-gray-700 dark:focus:ring-offset-gray-800"
            data-testid="check-email-signin-link">
            {{ t('web.auth.check_email.go_to_signin') }}
          </router-link>
        </div>
      </div>
    </template>

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
