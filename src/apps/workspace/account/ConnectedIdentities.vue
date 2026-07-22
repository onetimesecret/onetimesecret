<!-- src/apps/workspace/account/ConnectedIdentities.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { useConfirmDialog } from '@vueuse/core';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import ListSkeleton from '@/shared/components/closet/ListSkeleton.vue';
  import ConfirmDialog from '@/shared/components/modals/ConfirmDialog.vue';
  import SettingsLayout from '@/apps/workspace/layouts/SettingsLayout.vue';
  import { useConnectedIdentities } from '@/shared/composables/useConnectedIdentities';
  import { onMounted, ref } from 'vue';

  const { t } = useI18n();
  const { identities, isLoading, error, errorCode, fetchIdentities, removeIdentity, clearError } =
    useConnectedIdentities();

  // Friendly provider labels; unknown providers fall back to a capitalized name
  // so a backend that adds a strategy still renders sensibly.
  const PROVIDER_LABELS: Record<string, string> = {
    oidc: 'OpenID Connect',
    entra: 'Microsoft Entra',
    github: 'GitHub',
    google: 'Google',
  };
  const providerLabel = (provider: string): string =>
    PROVIDER_LABELS[provider] ?? provider.charAt(0).toUpperCase() + provider.slice(1);

  // Confirmation dialog for individual identity removal (mirrors ActiveSessions).
  const {
    isRevealed: isRemoveRevealed,
    reveal: revealRemove,
    confirm: confirmRemove,
    cancel: cancelRemove,
  } = useConfirmDialog();

  const pendingRemoveId = ref<number | null>(null);

  const handleRemove = async (id: number) => {
    clearError();
    pendingRemoveId.value = id;
    const { isCanceled } = await revealRemove();
    if (isCanceled) {
      pendingRemoveId.value = null;
      return;
    }
    await removeIdentity(id);
    pendingRemoveId.value = null;
  };

  onMounted(async () => {
    await fetchIdentities();
  });
</script>

<template>
  <SettingsLayout>
    <div>
      <div class="mb-6">
        <h1 class="text-3xl font-bold dark:text-white">
          {{ t('web.auth.connections.title') }}
        </h1>
        <p class="mt-2 text-gray-600 dark:text-gray-400">
          {{ t('web.auth.connections.description') }}
        </p>
      </div>

      <!-- Loading state -->
      <ListSkeleton
        v-if="isLoading && identities.length === 0"
        icon
        icon-size="w-5" />

      <template v-else>
        <!-- Error / lockout-guard message -->
        <div
          v-if="error"
          :class="[
            'mb-6 rounded-lg p-4',
            errorCode === 'last_credential'
              ? 'bg-yellow-50 dark:bg-yellow-900/20'
              : 'bg-red-50 dark:bg-red-900/20',
          ]"
          role="alert"
          data-testid="connections-error">
          <div class="flex items-center gap-3">
            <OIcon
              collection="heroicons"
              :name="
                errorCode === 'last_credential'
                  ? 'exclamation-triangle-solid'
                  : 'exclamation-circle-solid'
              "
              :class="[
                'size-5 shrink-0',
                errorCode === 'last_credential'
                  ? 'text-yellow-600 dark:text-yellow-400'
                  : 'text-red-600 dark:text-red-400',
              ]"
              aria-hidden="true" />
            <p
              :class="[
                'text-sm font-medium',
                errorCode === 'last_credential'
                  ? 'text-yellow-800 dark:text-yellow-200'
                  : 'text-red-800 dark:text-red-200',
              ]">
              {{ error }}
            </p>
            <button
              @click="clearError"
              type="button"
              class="ml-auto shrink-0 text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
              aria-label="Dismiss">
              <OIcon
                collection="heroicons"
                name="x-mark"
                class="size-5"
                aria-hidden="true" />
            </button>
          </div>
        </div>

        <!-- Identities card -->
        <div class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
          <div class="flex items-center gap-3">
            <div
              class="flex size-12 items-center justify-center rounded-lg bg-brand-100 dark:bg-brand-900/30">
              <OIcon
                collection="heroicons"
                name="globe-alt-solid"
                class="size-6 text-brand-600 dark:text-brand-400"
                aria-hidden="true" />
            </div>
            <div>
              <h2 class="text-xl font-semibold dark:text-white">
                {{ t('web.auth.connections.section_title') }}
              </h2>
              <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
                {{ t('web.auth.connections.section_subtitle') }}
              </p>
            </div>
          </div>

          <!-- Empty state -->
          <div
            v-if="identities.length === 0"
            class="mt-8 text-center"
            data-testid="connections-empty">
            <OIcon
              collection="heroicons"
              name="globe-alt"
              class="mx-auto size-12 text-gray-300 dark:text-gray-600"
              aria-hidden="true" />
            <h3 class="mt-4 text-lg font-medium text-gray-900 dark:text-white">
              {{ t('web.auth.connections.no_identities') }}
            </h3>
            <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
              {{ t('web.auth.connections.no_identities_description') }}
            </p>
          </div>

          <!-- Identities list -->
          <ul
            v-else
            class="mt-6 divide-y divide-gray-200 dark:divide-gray-700"
            data-testid="connections-list">
            <li
              v-for="identity in identities"
              :key="identity.id"
              class="flex items-center justify-between py-4">
              <div class="flex items-center gap-4">
                <OIcon
                  collection="heroicons"
                  name="key-solid"
                  class="size-5 shrink-0 text-gray-400"
                  aria-hidden="true" />
                <div>
                  <p class="font-medium text-gray-900 dark:text-white">
                    {{ providerLabel(identity.provider) }}
                  </p>
                  <!-- Issuer is hidden for the '' sentinel (legacy / OAuth2-only rows) -->
                  <p
                    v-if="identity.issuer"
                    class="break-all text-sm text-gray-500 dark:text-gray-400">
                    {{ t('web.auth.connections.issuer') }}: {{ identity.issuer }}
                  </p>
                  <p class="text-sm text-gray-500 dark:text-gray-400">
                    {{ t('web.auth.connections.identifier') }}: {{ identity.uid }}
                  </p>
                </div>
              </div>
              <button
                @click="handleRemove(identity.id)"
                type="button"
                :disabled="isLoading"
                :data-testid="`connections-remove-${identity.id}`"
                class="shrink-0 text-sm font-medium text-red-600 hover:text-red-500 disabled:cursor-not-allowed disabled:opacity-50 dark:text-red-400 dark:hover:text-red-300">
                {{ t('web.auth.connections.remove') }}
              </button>
            </li>
          </ul>
        </div>

        <!-- Related settings -->
        <div class="mt-6 rounded-lg bg-gray-50 p-4 dark:bg-gray-800">
          <h3
            class="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">
            {{ t('web.LABELS.related_settings') }}
          </h3>
          <div class="space-y-2">
            <router-link
              to="/account/settings/security/sessions"
              class="flex items-center gap-3 text-sm text-gray-700 hover:text-brand-600 dark:text-gray-300 dark:hover:text-brand-400">
              <OIcon
                collection="heroicons"
                name="computer-desktop-solid"
                class="size-4"
                aria-hidden="true" />
              <span>{{ t('web.auth.sessions.link_title') }}</span>
            </router-link>
            <router-link
              to="/account/settings/security/passkeys"
              class="flex items-center gap-3 text-sm text-gray-700 hover:text-brand-600 dark:text-gray-300 dark:hover:text-brand-400">
              <OIcon
                collection="heroicons"
                name="finger-print-solid"
                class="size-4"
                aria-hidden="true" />
              <span>{{ t('web.auth.passkeys.link_title') }}</span>
            </router-link>
          </div>
        </div>
      </template>

      <!-- Confirmation dialog for individual identity removal -->
      <ConfirmDialog
        v-if="isRemoveRevealed"
        @confirm="confirmRemove"
        @cancel="cancelRemove"
        :title="t('web.auth.connections.remove_confirm_title')"
        :message="t('web.auth.connections.remove_confirm_message')"
        type="danger" />
    </div>
  </SettingsLayout>
</template>
