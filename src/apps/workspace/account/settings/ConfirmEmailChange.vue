<!-- src/apps/workspace/account/settings/ConfirmEmailChange.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useAuth } from '@/shared/composables/useAuth';
  import { onMounted, ref } from 'vue';
  import { useRoute, useRouter } from 'vue-router';

  const { t } = useI18n();
  const route = useRoute();
  const router = useRouter();
  const {
    confirmEmailChange,
    isLoading,
    error,
  } = useAuth();

  const confirmed = ref(false);
  const redirectCountdown = ref(5);
  let countdownTimer: ReturnType<typeof setInterval> | undefined;

  const redirectToSignin = () => {
    if (countdownTimer) {
      clearInterval(countdownTimer);
    }
    router.push('/signin');
  };

  onMounted(async () => {
    const token = route.params.token as string;

    if (!token) {
      return;
    }

    const success = await confirmEmailChange(token);

    if (success) {
      confirmed.value = true;
      countdownTimer = setInterval(() => {
        redirectCountdown.value -= 1;
        if (redirectCountdown.value <= 0) {
          redirectToSignin();
        }
      }, 1000);
    }
  });
</script>

<template>
  <div
    class="flex min-h-[60vh] items-center
      justify-center px-4">
    <div class="w-full max-w-md text-center">
      <!-- Loading state -->
      <div v-if="isLoading">
        <OIcon
          collection="heroicons"
          name="arrow-path-solid"
          class="mx-auto size-8 animate-spin
            text-brand-500"
          aria-hidden="true" />
        <p
          class="mt-4 text-gray-600
            dark:text-gray-400">
          {{
            t('web.settings.profile.email_confirm_verifying')
          }}
        </p>
      </div>

      <!-- Success state -->
      <div v-else-if="confirmed">
        <div
          class="mx-auto flex size-16 items-center
            justify-center rounded-full bg-green-100
            dark:bg-green-900/30">
          <OIcon
            collection="heroicons"
            name="check-circle-solid"
            class="size-10 text-green-600
              dark:text-green-400"
            aria-hidden="true" />
        </div>
        <h1
          class="mt-6 text-2xl font-bold text-gray-900
            dark:text-white">
          {{
            t('web.settings.profile.confirm_email_change_title')
          }}
        </h1>
        <p
          class="mt-3 text-gray-600
            dark:text-gray-400">
          {{
            t('web.settings.profile.email_confirmed_success')
          }}
        </p>
        <p
          class="mt-4 text-sm text-gray-500
            dark:text-gray-500">
          {{
            t('web.settings.profile.redirecting_to_signin')
          }}
        </p>
        <router-link
          to="/signin"
          class="mt-4 inline-flex items-center gap-2
            text-sm font-medium text-brand-600
            hover:text-brand-700
            dark:text-brand-400
            dark:hover:text-brand-300"
          @click.prevent="redirectToSignin">
          {{
            t('web.COMMON.sign_in')
          }}
        </router-link>
      </div>

      <!-- Error state -->
      <div v-else-if="error">
        <div
          class="mx-auto flex size-16 items-center
            justify-center rounded-full bg-red-100
            dark:bg-red-900/30">
          <OIcon
            collection="heroicons"
            name="exclamation-circle-solid"
            class="size-10 text-red-600
              dark:text-red-400"
            aria-hidden="true" />
        </div>
        <h1
          class="mt-6 text-2xl font-bold text-gray-900
            dark:text-white">
          {{
            t('web.settings.profile.email_confirm_error_title')
          }}
        </h1>
        <p
          class="mt-3 text-red-600
            dark:text-red-400">
          {{
            t('web.settings.profile.email_confirm_invalid')
          }}
        </p>
        <router-link
          to="/account/settings/profile/email"
          class="mt-6 inline-flex items-center gap-2
            rounded-md bg-brand-600 px-4 py-2
            text-sm font-medium text-white
            hover:bg-brand-700
            dark:bg-brand-500
            dark:hover:bg-brand-600">
          {{
            t('web.settings.profile.email_confirm_back_to_settings')
          }}
        </router-link>
      </div>
    </div>
  </div>
</template>
