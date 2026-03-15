<!-- src/apps/session/components/AuthMethodSelector.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { isMagicLinksEnabled, isOmniAuthEnabled, isWebAuthnEnabled } from '@/utils/features';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { ref, computed } from 'vue';

import PasswordlessFirstSignIn from './PasswordlessFirstSignIn.vue';
import SignInForm from './SignInForm.vue';
import SsoButton from './SsoButton.vue';

const { t } = useI18n();
const bootstrapStore = useBootstrapStore();

export interface Props {
  locale?: string;
}

withDefaults(defineProps<Props>(), {
  locale: 'en',
});

type AuthMode = 'passwordless' | 'passkey' | 'password';

const emit = defineEmits<{
  (e: 'mode-change', mode: AuthMode): void;
}>();

// Check which methods are enabled
const magicLinksEnabled = isMagicLinksEnabled();
const webauthnEnabled = isWebAuthnEnabled();
const omniAuthEnabled = isOmniAuthEnabled();

// Extract SSO providers from bootstrap state
const ssoProviders = computed(() => {
  const omniauth = bootstrapStore.features?.omniauth;
  if (typeof omniauth === 'object' && omniauth !== null && Array.isArray(omniauth.providers)) {
    return omniauth.providers;
  }
  // Backward compatibility: single provider from legacy fields
  if (typeof omniauth === 'object' && omniauth !== null && omniauth.enabled) {
    return [{
      route_name: omniauth.route_name || 'oidc',
      display_name: omniauth.display_name || omniauth.provider_name || '',
    }];
  }
  return [];
});

// Show passwordless-first UI when any passwordless method is enabled
const hasPasswordlessMethods = computed(() => magicLinksEnabled || webauthnEnabled);

// Track current mode for footer context (emitted from PasswordlessFirstSignIn)
const currentMode = ref<AuthMode>('passwordless');

const handleModeChange = (mode: AuthMode) => {
  currentMode.value = mode;
  emit('mode-change', mode);
};

// Expose current mode for parent component (Login.vue) to use for footer
defineExpose({ currentMode });
</script>

<template>
  <div class="space-y-6">
    <!-- Passwordless-first mode when any passwordless method is enabled -->
    <PasswordlessFirstSignIn
      v-if="hasPasswordlessMethods"
      :locale="locale"
      :magic-links-enabled="magicLinksEnabled"
      :webauthn-enabled="webauthnEnabled"
      @mode-change="handleModeChange" />

    <!-- Password-only mode when no passwordless methods enabled -->
    <SignInForm
      v-else
      :locale="locale" />

    <!-- SSO section when OmniAuth is enabled -->
    <template v-if="omniAuthEnabled && ssoProviders.length > 0">
      <!-- Divider -->
      <div class="relative">
        <div class="absolute inset-0 flex items-center" aria-hidden="true">
          <div class="w-full border-t border-gray-300 dark:border-gray-600"></div>
        </div>
        <div class="relative flex justify-center text-sm">
          <span class="bg-white px-2 text-gray-500 dark:bg-gray-800 dark:text-gray-400">
            {{ t('web.login.or_continue_with') }}
          </span>
        </div>
      </div>

      <!-- SSO Buttons — one per configured provider -->
      <div class="space-y-3">
        <SsoButton
          v-for="provider in ssoProviders"
          :key="provider.route_name"
          :route-name="provider.route_name"
          :display-name="provider.display_name" />
      </div>
    </template>
  </div>
</template>
