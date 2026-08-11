<!-- src/apps/workspace/account/PasskeySettings.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import ListSkeleton from '@/shared/components/closet/ListSkeleton.vue';
  import SettingsLayout from '@/apps/workspace/layouts/SettingsLayout.vue';
  import ConfirmDialog from '@/shared/components/modals/ConfirmDialog.vue';
  import PasswordConfirmModal from '@/shared/components/modals/PasswordConfirmModal.vue';
  import { useWebAuthn } from '@/shared/composables/useWebAuthn';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { formatDisplayDateTime } from '@/utils/format';
  import { computed, onMounted, ref, watch } from 'vue';

  const { t } = useI18n();
  const {
    supported,
    isLoading,
    error,
    registerWebAuthn,
    fetchWebAuthnCredentials,
    removeWebAuthn,
    clearError,
  } = useWebAuthn();
  const bootstrapStore = useBootstrapStore();

  // Local state
  const isRegistering = ref(false);
  const successMessage = ref<string | null>(null);
  const showPasswordModal = ref(false);
  const passwordError = ref<string | null>(null);

  // Removal flow state
  const pendingRemovalId = ref<string | null>(null);
  const showRemovePasswordModal = ref(false);
  const showRemoveConfirm = ref(false);
  const isRemoving = ref(false);

  // The credentials table stores no name and no created_at — id plus
  // last_used_at is the entire per-passkey shape.
  interface Passkey {
    id: string;
    last_used_at: string | null;
  }

  const passkeys = ref<Passkey[]>([]);
  const isLoadingPasskeys = ref(false);

  // SSO-only accounts have no local password: skip the password prompt and let
  // the backend validate (it only checks a password for accounts that have
  // one). Read has_password from the bootstrap store — available synchronously
  // at mount (no async gap where an SSO-only user could get an unsatisfiable
  // prompt) and refreshed by useAuth when the account later sets a password.
  // Anything other than an explicit false keeps the password prompt.
  const requiresPassword = computed(() => bootstrapStore.has_password !== false);

  const fetchPasskeys = async () => {
    isLoadingPasskeys.value = true;
    const credentials = await fetchWebAuthnCredentials();
    if (credentials) {
      passkeys.value = credentials;
    }
    isLoadingPasskeys.value = false;
  };

  onMounted(async () => {
    await fetchPasskeys();
  });

  // Sync error from composable to whichever password modal is open
  watch(error, (newError) => {
    if (newError && (showPasswordModal.value || showRemovePasswordModal.value)) {
      passwordError.value = newError;
    }
  });

  // Register a passkey after a successful ceremony, then refresh the list
  const performRegistration = async (password?: string): Promise<boolean> => {
    const success = await registerWebAuthn(password);
    if (success) {
      successMessage.value = t('web.auth.passkeys.registered_success');
      await fetchPasskeys();
    }
    return success;
  };

  // Add passkey: password-holding accounts confirm via modal first; SSO-only
  // accounts (has_password === false) go straight to the browser ceremony.
  const handleAddPasskeyClick = async () => {
    clearError();
    successMessage.value = null;
    passwordError.value = null;

    if (requiresPassword.value) {
      showPasswordModal.value = true;
      return;
    }

    isRegistering.value = true;
    await performRegistration();
    isRegistering.value = false;
  };

  // Handle password confirmation and register passkey
  const handlePasswordConfirm = async (password: string) => {
    passwordError.value = null;
    isRegistering.value = true;

    const success = await performRegistration(password);

    if (success) {
      showPasswordModal.value = false;
    } else {
      // Error is set by the composable, sync to modal
      passwordError.value = error.value;
    }

    isRegistering.value = false;
  };

  // Handle modal cancel
  const handlePasswordCancel = () => {
    showPasswordModal.value = false;
    passwordError.value = null;
    clearError();
  };

  // Remove passkey: confirm first — via PasswordConfirmModal when the account
  // has a password, via a plain ConfirmDialog otherwise (same pattern as
  // ActiveSessions individual-session removal).
  const handleRemoveClick = (credentialId: string) => {
    clearError();
    successMessage.value = null;
    passwordError.value = null;
    pendingRemovalId.value = credentialId;

    if (requiresPassword.value) {
      showRemovePasswordModal.value = true;
    } else {
      showRemoveConfirm.value = true;
    }
  };

  const performRemoval = async (password?: string): Promise<boolean> => {
    if (!pendingRemovalId.value) return false;

    const success = await removeWebAuthn(pendingRemovalId.value, password);
    if (success) {
      successMessage.value = t('web.auth.passkeys.removed_success');
      pendingRemovalId.value = null;
      await fetchPasskeys();
    }
    return success;
  };

  const handleRemovePasswordConfirm = async (password: string) => {
    passwordError.value = null;
    isRemoving.value = true;

    const success = await performRemoval(password);

    if (success) {
      showRemovePasswordModal.value = false;
    } else {
      passwordError.value = error.value;
    }

    isRemoving.value = false;
  };

  const handleRemoveConfirm = async () => {
    showRemoveConfirm.value = false;
    isRemoving.value = true;
    await performRemoval();
    isRemoving.value = false;
  };

  const handleRemoveCancel = () => {
    showRemoveConfirm.value = false;
    showRemovePasswordModal.value = false;
    pendingRemovalId.value = null;
    passwordError.value = null;
    clearError();
  };

  // Clear messages
  const clearMessages = () => {
    clearError();
    successMessage.value = null;
  };

  // Format date for display
  const formatDate = (dateString: string | null): string => {
    if (!dateString) return t('web.auth.passkeys.never_used');
    return formatDisplayDateTime(new Date(dateString));
  };

  // Short id suffix so multiple passkeys are distinguishable (credentials
  // carry no user-visible name)
  const idSuffix = (credentialId: string): string => credentialId.slice(-6);
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
      <ListSkeleton
        v-if="isLoadingPasskeys"
        icon
        icon-size="w-5" />

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
              @click="handleAddPasskeyClick"
              type="button"
              :disabled="isLoading"
              class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50">
              <OIcon
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
                    {{ t('web.auth.passkeys.name') }}
                    <span class="font-mono text-sm text-gray-500 dark:text-gray-400"
                      >#{{ idSuffix(passkey.id) }}</span
                    >
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
                @click="handleRemoveClick(passkey.id)"
                type="button"
                :disabled="isRemoving || isLoading"
                class="text-sm font-medium text-red-600 hover:text-red-500 disabled:cursor-not-allowed disabled:opacity-50 dark:text-red-400 dark:hover:text-red-300">
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

      <!-- Password Confirmation Modal for Passkey Setup -->
      <PasswordConfirmModal
        v-model:open="showPasswordModal"
        :title="t('web.auth.passkeys.add_passkey')"
        :description="t('web.COMMON.password_required_for_action')"
        :loading="isRegistering"
        :error="passwordError"
        @confirm="handlePasswordConfirm"
        @cancel="handlePasswordCancel">
        <template #icon>
          <OIcon
            collection="heroicons"
            name="finger-print"
            class="size-6 text-brand-600 dark:text-brand-400"
            aria-hidden="true" />
        </template>
      </PasswordConfirmModal>

      <!-- Password Confirmation Modal for Passkey Removal (accounts with a password) -->
      <PasswordConfirmModal
        v-model:open="showRemovePasswordModal"
        :title="t('web.auth.passkeys.remove_passkey')"
        :description="t('web.auth.passkeys.confirm_remove')"
        variant="danger"
        :loading="isRemoving"
        :error="passwordError"
        @confirm="handleRemovePasswordConfirm"
        @cancel="handleRemoveCancel" />

      <!-- Plain confirmation for Passkey Removal (SSO-only accounts, no password) -->
      <ConfirmDialog
        v-if="showRemoveConfirm"
        :title="t('web.auth.passkeys.remove_passkey')"
        :message="t('web.auth.passkeys.confirm_remove')"
        type="danger"
        @confirm="handleRemoveConfirm"
        @cancel="handleRemoveCancel" />
    </div>
  </SettingsLayout>
</template>
