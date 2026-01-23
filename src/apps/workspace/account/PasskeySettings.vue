<!-- src/apps/workspace/account/PasskeySettings.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import SettingsLayout from '@/apps/workspace/layouts/SettingsLayout.vue';
  import { useWebAuthn } from '@/shared/composables/useWebAuthn';
  import { onMounted, ref } from 'vue';

  const { t } = useI18n();
  const { supported, isLoading, error, registerWebAuthn, clearError } = useWebAuthn();

  // Local state
  const isRegistering = ref(false);
  const successMessage = ref<string | null>(null);

  // Passkey list - would be populated from API in full implementation
  // For now, we show the registration flow
  interface Passkey {
    id: string;
    name: string;
    created_at: string;
    last_used_at: string | null;
  }

  const passkeys = ref<Passkey[]>([]);
  const isLoadingPasskeys = ref(false);

  onMounted(async () => {
    // TODO: Fetch passkeys list from API when endpoint is available
    // await fetchPasskeys();
  });

  // Register new passkey
  const handleRegisterPasskey = async () => {
    clearError();
    successMessage.value = null;
    isRegistering.value = true;

    const success = await registerWebAuthn();

    if (success) {
      successMessage.value = t('web.auth.passkeys.registered_success');
      // TODO: Refresh passkeys list when API is available
    }

    isRegistering.value = false;
  };

  // Clear messages
  const clearMessages = () => {
    clearError();
    successMessage.value = null;
  };

  // Format date for display
  const formatDate = (dateString: string | null): string => {
    if (!dateString) return t('web.auth.passkeys.never_used');
    return new Date(dateString).toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };
</script>

<template>
  <SettingsLayout>
    <div>
      <div class="mb-6">
        <h1 class="text-3xl font-bold dark:text-white">
          {{ t('web.auth.passkeys.title') }}
        </h1>
        <p class="mt-2 text-gray-600 dark:text-gray-400">
          {{ t('web.auth.passkeys.setup_description') }}
        </p>
      </div>

      <!-- Loading state -->
      <div
        v-if="isLoadingPasskeys"
        class="flex items-center justify-center py-12">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          class="mr-2 size-6 animate-spin text-gray-400"
          aria-hidden="true" />
        <span class="text-gray-600 dark:text-gray-400">Loading passkeys...</span>
      </div>

      <!-- Browser not supported -->
      <div
        v-else-if="!supported"
        class="rounded-lg bg-yellow-50 p-6 dark:bg-yellow-900/20"
        role="alert">
        <div class="flex items-center gap-3">
          <OIcon
            collection="heroicons"
            name="exclamation-triangle-solid"
            class="size-8 text-yellow-600 dark:text-yellow-400"
            aria-hidden="true" />
          <div>
            <h3 class="font-semibold text-yellow-800 dark:text-yellow-200">
              {{ t('web.auth.webauthn.notSupported') }}
            </h3>
            <p class="mt-1 text-sm text-yellow-700 dark:text-yellow-300">
              {{ t('web.auth.webauthn.requiresModernBrowser') }}
            </p>
          </div>
        </div>
      </div>

      <!-- Main content -->
      <div
        v-else
        class="space-y-6">
        <!-- Success message -->
        <div
          v-if="successMessage"
          class="rounded-lg bg-green-50 p-4 dark:bg-green-900/20"
          role="status">
          <div class="flex items-center gap-3">
            <OIcon
              collection="heroicons"
              name="check-circle-solid"
              class="size-5 text-green-600 dark:text-green-400"
              aria-hidden="true" />
            <p class="text-sm font-medium text-green-800 dark:text-green-200">
              {{ successMessage }}
            </p>
            <button
              @click="clearMessages"
              type="button"
              class="ml-auto text-green-600 hover:text-green-500 dark:text-green-400"
              aria-label="Dismiss">
              <OIcon
                collection="heroicons"
                name="x-mark"
                class="size-5"
                aria-hidden="true" />
            </button>
          </div>
        </div>

        <!-- Error message -->
        <div
          v-if="error"
          class="rounded-lg bg-red-50 p-4 dark:bg-red-900/20"
          role="alert">
          <div class="flex items-center gap-3">
            <OIcon
              collection="heroicons"
              name="exclamation-circle-solid"
              class="size-5 text-red-600 dark:text-red-400"
              aria-hidden="true" />
            <p class="text-sm font-medium text-red-800 dark:text-red-200">
              {{ error }}
            </p>
            <button
              @click="clearMessages"
              type="button"
              class="ml-auto text-red-600 hover:text-red-500 dark:text-red-400"
              aria-label="Dismiss">
              <OIcon
                collection="heroicons"
                name="x-mark"
                class="size-5"
                aria-hidden="true" />
            </button>
          </div>
        </div>

        <!-- Passkeys list -->
        <div class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
          <div class="flex items-start justify-between">
            <div class="flex items-center gap-3">
              <div class="flex size-12 items-center justify-center rounded-lg bg-brand-100 dark:bg-brand-900/30">
                <OIcon
                  collection="heroicons"
                  name="finger-print-solid"
                  class="size-6 text-brand-600 dark:text-brand-400"
                  aria-hidden="true" />
              </div>
              <div>
                <h2 class="text-xl font-semibold dark:text-white">
                  {{ t('web.auth.passkeys.title') }}
                </h2>
                <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
                  {{ t('web.auth.webauthn.supportedMethods') }}
                </p>
              </div>
            </div>

            <!-- Add passkey button -->
            <button
              @click="handleRegisterPasskey"
              type="button"
              :disabled="isLoading || isRegistering"
              class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50">
              <OIcon
                v-if="isRegistering"
                collection="heroicons"
                name="arrow-path"
                class="size-4 animate-spin"
                aria-hidden="true" />
              <OIcon
                v-else
                collection="heroicons"
                name="plus"
                class="size-4"
                aria-hidden="true" />
              <span>{{ t('web.auth.passkeys.add_passkey') }}</span>
            </button>
          </div>

          <!-- Empty state -->
          <div
            v-if="passkeys.length === 0"
            class="mt-8 text-center">
            <OIcon
              collection="heroicons"
              name="finger-print"
              class="mx-auto size-12 text-gray-300 dark:text-gray-600"
              aria-hidden="true" />
            <h3 class="mt-4 text-lg font-medium text-gray-900 dark:text-white">
              {{ t('web.auth.passkeys.no_passkeys') }}
            </h3>
            <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
              {{ t('web.auth.passkeys.no_passkeys_description') }}
            </p>
          </div>

          <!-- Passkeys list -->
          <div
            v-else
            class="mt-6 divide-y divide-gray-200 dark:divide-gray-700">
            <div
              v-for="passkey in passkeys"
              :key="passkey.id"
              class="flex items-center justify-between py-4">
              <div class="flex items-center gap-4">
                <OIcon
                  collection="heroicons"
                  name="key-solid"
                  class="size-5 text-gray-400"
                  aria-hidden="true" />
                <div>
                  <p class="font-medium text-gray-900 dark:text-white">
                    {{ passkey.name }}
                  </p>
                  <p class="text-sm text-gray-500 dark:text-gray-400">
                    {{ t('web.auth.passkeys.created') }}: {{ formatDate(passkey.created_at) }}
                  </p>
                  <p class="text-sm text-gray-500 dark:text-gray-400">
                    {{
                      passkey.last_used_at
                        ? t('web.auth.passkeys.last_used', { time: formatDate(passkey.last_used_at) })
                        : t('web.auth.passkeys.never_used')
                    }}
                  </p>
                </div>
              </div>
              <button
                type="button"
                class="text-sm font-medium text-red-600 hover:text-red-500 dark:text-red-400 dark:hover:text-red-300">
                {{ t('web.auth.passkeys.remove_passkey') }}
              </button>
            </div>
          </div>
        </div>

        <!-- Benefits section -->
        <div class="rounded-lg bg-gray-50 p-6 dark:bg-gray-800">
          <h3 class="mb-4 text-sm font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">
            {{ t('web.LABELS.benefits') }}
          </h3>
          <ul class="space-y-3 text-sm text-gray-600 dark:text-gray-400">
            <li class="flex items-start gap-3">
              <OIcon
                collection="heroicons"
                name="shield-check-solid"
                class="mt-0.5 size-5 shrink-0 text-green-500"
                aria-hidden="true" />
              <span>{{ t('web.auth.passkeys.benefit_secure') }}</span>
            </li>
            <li class="flex items-start gap-3">
              <OIcon
                collection="heroicons"
                name="bolt-solid"
                class="mt-0.5 size-5 shrink-0 text-green-500"
                aria-hidden="true" />
              <span>{{ t('web.auth.passkeys.benefit_fast') }}</span>
            </li>
            <li class="flex items-start gap-3">
              <OIcon
                collection="heroicons"
                name="cloud-solid"
                class="mt-0.5 size-5 shrink-0 text-green-500"
                aria-hidden="true" />
              <span>{{ t('web.auth.passkeys.benefit_synced') }}</span>
            </li>
          </ul>
        </div>

        <!-- Quick links -->
        <div class="rounded-lg bg-gray-50 p-4 dark:bg-gray-800">
          <h3 class="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">
            {{ t('web.LABELS.related_settings') }}
          </h3>
          <div class="space-y-2">
            <router-link
              to="/account/settings/security/mfa"
              class="flex items-center gap-3 text-sm text-gray-700 hover:text-brand-600 dark:text-gray-300 dark:hover:text-brand-400">
              <OIcon
                collection="heroicons"
                name="key"
                class="size-4"
                aria-hidden="true" />
              <span>{{ t('web.auth.mfa.title') }}</span>
            </router-link>
            <router-link
              to="/account/settings/security/recovery-codes"
              class="flex items-center gap-3 text-sm text-gray-700 hover:text-brand-600 dark:text-gray-300 dark:hover:text-brand-400">
              <OIcon
                collection="heroicons"
                name="document-text-solid"
                class="size-4"
                aria-hidden="true" />
              <span>{{ t('web.auth.recovery_codes.link_title') }}</span>
            </router-link>
          </div>
        </div>
      </div>
    </div>
  </SettingsLayout>
</template>
