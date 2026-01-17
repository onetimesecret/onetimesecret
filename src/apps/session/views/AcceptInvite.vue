<!-- src/apps/session/views/AcceptInvite.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import BasicFormAlerts from '@/shared/components/forms/BasicFormAlerts.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useAsyncHandler } from '@/shared/composables/useAsyncHandler';
  import { classifyError } from '@/schemas/errors';
  import { useAuth } from '@/shared/composables/useAuth';
  import { useAuthStore } from '@/shared/stores/authStore';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useOrganizationStore } from '@/shared/stores/organizationStore';
  import { inject, onMounted, ref, computed } from 'vue';
  import { useRoute, useRouter } from 'vue-router';
  import type { AxiosInstance } from 'axios';
  import { z } from 'zod';

  const { t } = useI18n();
  const route = useRoute();
  const router = useRouter();
  const authStore = useAuthStore();
  const bootstrapStore = useBootstrapStore();
  const organizationStore = useOrganizationStore();
  const { logout } = useAuth();
  const $api = inject('api') as AxiosInstance;

  const { wrap } = useAsyncHandler({
    notify: false,
  });

  const invitationToken = ref<string>(route.params.token as string);
  const invitation = ref<{
    organization_name: string;
    organization_id: string;
    email: string;
    role: string;
    invited_by_email: string;
    expires_at: number;
    status: string;
  } | null>(null);

  const isLoading = ref(true);
  const error = ref('');
  const success = ref('');
  const isProcessing = ref(false);

  const invitationSchema = z.object({
    organization_name: z.string(),
    organization_id: z.string(),
    email: z.string().email(),
    role: z.string(),
    invited_by_email: z.string(),
    expires_at: z.number(),
    status: z.string(),
  });

  /**
   * Normalizes an email address for comparison.
   * - Lowercases the entire email
   * - Strips Gmail-style + suffixes (user+tag@gmail.com → user@gmail.com)
   */
  function normalizeEmail(email: string): string {
    const [local, domain] = email.toLowerCase().split('@');
    if (!domain) return email.toLowerCase();
    const normalizedLocal = local.split('+')[0];
    return `${normalizedLocal}@${domain}`;
  }

  /**
   * Detects if the currently logged-in user has a different email
   * than the one the invitation was sent to.
   */
  const emailMismatch = computed(() => {
    if (!authStore.isAuthenticated || !invitation.value?.email) return false;
    const currentEmail = bootstrapStore.email;
    if (!currentEmail) return false;
    return normalizeEmail(currentEmail) !== normalizeEmail(invitation.value.email);
  });

  /**
   * Logs out the current user and redirects to sign in with the invited email prefilled.
   */
  async function handleSwitchAccount() {
    const invitedEmail = invitation.value?.email;
    const token = invitationToken.value;

    // Build the signin URL with email prefill and redirect back to invitation
    const signinUrl = `/signin?email=${encodeURIComponent(invitedEmail || '')}&redirect=${encodeURIComponent(`/invite/${token}`)}`;

    // Pass the redirect URL to logout - it handles the navigation via window.location.href
    await logout(signinUrl);
    // No router.push needed - logout handles the redirect
  }

  onMounted(async () => {
    const result = await wrap(async () => {
      const response = await $api.get(`/api/invite/${invitationToken.value}`);
      return invitationSchema.parse(response.data.record);
    });

    if (result) {
      invitation.value = result;

      if (result.status === 'expired') {
        error.value = t('web.organizations.invitations.expired_message');
      } else if (result.status !== 'pending') {
        error.value = t('web.organizations.invitations.invalid_token');
      }
    } else {
      error.value = t('web.organizations.invitations.invalid_token');
    }

    isLoading.value = false;
  });

  const handleAccept = async () => {
    if (!authStore.isAuthenticated) {
      router.push({
        name: 'Sign In',
        query: {
          email: invitation.value?.email,
          redirect: `/invite/${invitationToken.value}`,
        },
      });
      return;
    }

    isProcessing.value = true;
    error.value = '';
    success.value = '';

    try {
      await $api.post(`/api/invite/${invitationToken.value}/accept`);

      success.value = t('web.organizations.invitations.accept_success');

      // Reset organization store to force refetch on next mount
      organizationStore.$reset();

      setTimeout(() => {
        router.push('/org');
      }, 2000);
    } catch (err) {
      const classified = classifyError(err);
      error.value = classified.message || t('web.organizations.invitations.accept_error');
    } finally {
      isProcessing.value = false;
    }
  };

  const handleDecline = async () => {
    isProcessing.value = true;
    error.value = '';

    try {
      await $api.post(`/api/invite/${invitationToken.value}/decline`);

      // Update local state to hide invitation details immediately
      if (invitation.value) {
        invitation.value.status = 'declined';
      }
      success.value = t('web.organizations.invitations.decline_success');

      setTimeout(() => {
        router.push('/');
      }, 2000);
    } catch (err) {
      const classified = classifyError(err);
      error.value = classified.message || t('web.organizations.invitations.decline_error');
    } finally {
      isProcessing.value = false;
    }
  };

  const formatDate = (timestamp: number): string => new Date(timestamp * 1000).toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
</script>

<template>
  <div class="mx-auto max-w-md px-4 py-8 sm:px-6 lg:px-8">
    <!-- Loading State -->
    <div
      v-if="isLoading"
      class="flex items-center justify-center py-12">
      <div class="text-center">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          class="mx-auto size-8 animate-spin text-gray-400"
          aria-hidden="true" />
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.organizations.invitations.loading_invitation') }}
        </p>
      </div>
    </div>

    <!-- Invitation Content -->
    <div
      v-else
      class="rounded-lg border border-gray-200 bg-white p-8 shadow-sm dark:border-gray-700 dark:bg-gray-800">
      <!-- Header -->
      <div class="mb-6 text-center">
        <OIcon
          collection="heroicons"
          name="envelope"
          class="mx-auto size-12 text-brand-600 dark:text-brand-400"
          aria-hidden="true" />
        <h1 class="mt-4 text-2xl font-bold text-gray-900 dark:text-white">
          {{ t('web.organizations.invitations.invitation_details') }}
        </h1>
      </div>

      <BasicFormAlerts
        v-if="error"
        :error="error" />
      <BasicFormAlerts
        v-if="success"
        :success="success" />

      <!-- Invitation Details -->
      <div
        v-if="invitation && invitation.status === 'pending'"
        class="space-y-4">
        <div class="rounded-lg bg-gray-50 p-4 dark:bg-gray-700/50">
          <p class="mb-2 text-sm text-gray-600 dark:text-gray-400">
            {{ t('web.organizations.invitations.you_are_invited') }}
          </p>
          <p class="text-lg font-semibold text-gray-900 dark:text-white">
            {{ invitation.organization_name }}
          </p>
        </div>

        <div class="space-y-2 text-sm">
          <div class="flex justify-between">
            <span class="text-gray-600 dark:text-gray-400">
              {{ t('web.organizations.invitations.email_address') }}
            </span>
            <span class="font-medium text-gray-900 dark:text-white">
              {{ invitation.email }}
            </span>
          </div>

          <div class="flex justify-between">
            <span class="text-gray-600 dark:text-gray-400">
              {{ t('web.organizations.invitations.invited_as') }}
            </span>
            <span class="font-medium text-gray-900 dark:text-white">
              {{ t(`web.organizations.invitations.roles.${invitation.role}`) }}
            </span>
          </div>

          <div class="flex justify-between">
            <span class="text-gray-600 dark:text-gray-400">
              {{ t('web.organizations.invitations.invited_by') }}
            </span>
            <span class="font-medium text-gray-900 dark:text-white">
              {{ invitation.invited_by_email }}
            </span>
          </div>

          <div class="flex justify-between">
            <span class="text-gray-600 dark:text-gray-400">
              {{ t('web.organizations.invitations.expires_at') }}
            </span>
            <span class="font-medium text-gray-900 dark:text-white">
              {{ formatDate(invitation.expires_at) }}
            </span>
          </div>
        </div>

        <!-- Email Mismatch Warning (authenticated but wrong email) -->
        <div
          v-if="emailMismatch"
          class="rounded-lg border border-amber-200 bg-amber-50 p-4 dark:border-amber-800 dark:bg-amber-900/20">
          <div class="flex">
            <OIcon
              collection="heroicons"
              name="exclamation-triangle"
              class="size-5 shrink-0 text-amber-500"
              aria-hidden="true" />
            <div class="ml-3">
              <p class="font-medium text-amber-800 dark:text-amber-200">
                {{ t('web.organizations.invitations.email_mismatch_title') }}
              </p>
              <p class="mt-1 text-sm text-amber-700 dark:text-amber-300">
                {{ t('web.organizations.invitations.email_mismatch_body', {
                  invitedEmail: invitation?.email,
                  currentEmail: bootstrapStore.email
                }) }}
              </p>
              <div class="mt-3">
                <button
                  type="button"
                  @click="handleSwitchAccount"
                  :disabled="isProcessing"
                  class="inline-flex items-center rounded-md bg-amber-100 px-3 py-1.5 text-sm font-medium text-amber-800 hover:bg-amber-200 focus:outline-none focus:ring-2 focus:ring-amber-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-amber-800 dark:text-amber-100 dark:hover:bg-amber-700">
                  {{ t('web.organizations.invitations.switch_account') }}
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- Sign In Notice (unauthenticated) -->
        <div
          v-else-if="!authStore.isAuthenticated"
          class="rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/20">
          <div class="flex">
            <OIcon
              collection="heroicons"
              name="information-circle"
              class="size-5 text-blue-400"
              aria-hidden="true" />
            <div class="ml-3">
              <p class="text-sm text-blue-800 dark:text-blue-400">
                {{ t('web.organizations.invitations.must_sign_in') }}
              </p>
            </div>
          </div>
        </div>

        <!-- Action Buttons -->
        <div class="mt-6 flex flex-col gap-3 sm:flex-row-reverse">
          <button
            type="button"
            @click="handleAccept"
            :disabled="isProcessing"
            class="inline-flex w-full justify-center rounded-md bg-brand-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400 sm:w-auto">
            <span v-if="!isProcessing">
              {{ t('web.organizations.invitations.accept_invitation') }}
            </span>
            <span v-else>{{ t('web.COMMON.processing') }}</span>
          </button>
          <button
            type="button"
            @click="handleDecline"
            :disabled="isProcessing"
            class="inline-flex w-full justify-center rounded-md bg-white px-4 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-100 dark:ring-gray-600 dark:hover:bg-gray-600 sm:w-auto">
            {{ t('web.organizations.invitations.decline_invitation') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
