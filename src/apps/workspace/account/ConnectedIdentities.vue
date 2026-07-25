<!-- src/apps/workspace/account/ConnectedIdentities.vue -->

<script setup lang="ts">
  import SettingsLayout from '@/apps/workspace/layouts/SettingsLayout.vue';
  import ListSkeleton from '@/shared/components/closet/ListSkeleton.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import ConfirmDialog from '@/shared/components/modals/ConfirmDialog.vue';
  import { useConnectedIdentities } from '@/shared/composables/useConnectedIdentities';
  import { useCsrfStore } from '@/shared/stores/csrfStore';
  import { submitSsoLogin } from '@/shared/utils/sso';
  // Two label helpers on purpose: linked rows name the provider canonically
  // (providerLabel), connect buttons prefer the operator's display_name
  // (configuredProviderLabel). See the docblocks in utils/features.ts.
  import {
    configuredProviderLabel,
    getSsoProviders,
    providerLabel,
    type SsoProvider,
  } from '@/utils/features';
  import { useConfirmDialog } from '@vueuse/core';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();
  const csrfStore = useCsrfStore();
  const { identities, isLoading, error, errorCode, fetchIdentities, removeIdentity, clearError } =
    useConnectedIdentities();

  // Providers the account can still link. A provider is "already linked" when
  // its route_name matches the `provider` of any existing identity row (both are
  // the omniauth route name, e.g. 'oidc'). Exclude-by-route is correct here: on
  // the platform / self-host surface a route maps to a single issuer.
  const CONNECT_REDIRECT = '/account/settings/security/connections';

  const connectableProviders = computed<SsoProvider[]>(() => {
    const linked = new Set(identities.value.map((identity) => identity.provider));
    return getSsoProviders().filter((provider) => !linked.has(provider.route_name));
  });

  // Connecting reuses the sign-in form POST (see submitSsoLogin) but marks it
  // with connect: true so the backend hook binds the returned identity to the
  // logged-in account (a plain sign-in stays unmarked and never binds).
  // `redirect` brings the user back to this panel after the IdP round-trip.
  const handleConnect = (provider: SsoProvider) => {
    submitSsoLogin({
      routeName: provider.route_name,
      shrimp: csrfStore.shrimp,
      redirect: CONNECT_REDIRECT,
      connect: true,
    });
  };

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
            <!-- prettier-ignore-attribute class -->
            <button
              @click="clearError"
              type="button"
              class="
                ml-auto shrink-0 text-gray-500 hover:text-gray-700
                dark:text-gray-400 dark:hover:text-gray-200"
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
            <!-- prettier-ignore-attribute class -->
            <div
              class="
                flex size-12 items-center justify-center rounded-lg
                bg-brand-100 dark:bg-brand-900/30">
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
                    class="text-sm break-all text-gray-500 dark:text-gray-400">
                    {{ t('web.auth.connections.issuer') }}: {{ identity.issuer }}
                  </p>
                  <p class="text-sm text-gray-500 dark:text-gray-400">
                    {{ t('web.auth.connections.identifier') }}: {{ identity.uid }}
                  </p>
                </div>
              </div>
              <!-- prettier-ignore-attribute class -->
              <button
                @click="handleRemove(identity.id)"
                type="button"
                :disabled="isLoading"
                :data-testid="`connections-remove-${identity.id}`"
                class="
                  shrink-0 text-sm font-medium text-red-600 hover:text-red-500
                  disabled:cursor-not-allowed disabled:opacity-50
                  dark:text-red-400 dark:hover:text-red-300">
                {{ t('web.auth.connections.remove') }}
              </button>
            </li>
          </ul>

          <!-- Connect a provider: shown in both empty and populated states as
               long as there is at least one provider not yet linked. -->
          <div
            v-if="connectableProviders.length > 0"
            class="mt-6 border-t border-gray-200 pt-6 dark:border-gray-700"
            data-testid="connections-connect">
            <h3 class="text-sm font-medium text-gray-900 dark:text-white">
              {{ t('web.auth.connections.connect_title') }}
            </h3>
            <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              {{ t('web.auth.connections.connect_description') }}
            </p>
            <div class="mt-4 flex flex-wrap gap-3">
              <!-- prettier-ignore-attribute class -->
              <button
                v-for="provider in connectableProviders"
                :key="provider.route_name"
                @click="handleConnect(provider)"
                type="button"
                :data-testid="`connections-connect-${provider.route_name}`"
                class="
                  inline-flex items-center gap-2 rounded-lg border border-brand-200
                  bg-brand-50 px-4 py-2 text-sm font-medium text-brand-700 transition-colors
                  hover:bg-brand-100 dark:border-brand-800 dark:bg-brand-900/20
                  dark:text-brand-300 dark:hover:bg-brand-900/40">
                <OIcon
                  collection="heroicons"
                  name="link-solid"
                  class="size-5 shrink-0"
                  aria-hidden="true" />
                {{
                  t('web.auth.connections.connect_action', {
                    provider: configuredProviderLabel(provider),
                  })
                }}
              </button>
            </div>
          </div>
        </div>

        <!-- Related settings -->
        <div class="mt-6 rounded-lg bg-gray-50 p-4 dark:bg-gray-800">
          <!-- prettier-ignore-attribute class -->
          <h3
            class="
              mb-3 text-sm font-semibold tracking-wide text-gray-500 uppercase
              dark:text-gray-400">
            {{ t('web.LABELS.related_settings') }}
          </h3>
          <div class="space-y-2">
            <!-- prettier-ignore-attribute class -->
            <router-link
              to="/account/settings/security/sessions"
              class="
                flex items-center gap-3 text-sm text-gray-700 hover:text-brand-600
                dark:text-gray-300 dark:hover:text-brand-400">
              <OIcon
                collection="heroicons"
                name="computer-desktop-solid"
                class="size-4"
                aria-hidden="true" />
              <span>{{ t('web.auth.sessions.link_title') }}</span>
            </router-link>
            <!-- prettier-ignore-attribute class -->
            <router-link
              to="/account/settings/security/passkeys"
              class="
                flex items-center gap-3 text-sm text-gray-700 hover:text-brand-600
                dark:text-gray-300 dark:hover:text-brand-400">
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
