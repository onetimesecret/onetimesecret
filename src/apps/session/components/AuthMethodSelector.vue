<!-- src/apps/session/components/AuthMethodSelector.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import { useProductIdentity } from '@/shared/stores/identityStore';
import { isMagicLinksEnabled, isSsoEnabled, isWebAuthnEnabled, getSsoProviders, isSsoOnlyMode } from '@/utils/features';
import { ref, computed } from 'vue';

import PasswordlessFirstSignIn from './PasswordlessFirstSignIn.vue';
import SignInForm from './SignInForm.vue';
import SsoButton from './SsoButton.vue';

const { t } = useI18n();

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

// Custom domains force SSO-only authentication
const { isCustom } = useProductIdentity();

// Check which methods are enabled
const magicLinksEnabled = isMagicLinksEnabled();
const webauthnEnabled = isWebAuthnEnabled();
const ssoEnabled = isSsoEnabled();
const ssoOnly = computed(() => isSsoOnlyMode());

// Extract SSO providers via feature utility
const ssoProviders = computed(() => getSsoProviders());

// SSO-only mode: show only SSO buttons when:
// - explicit sso_only mode is active, OR
// - on a custom domain (org members must use SSO)
const showSsoOnly = computed(() =>
  (ssoOnly.value || isCustom) && ssoEnabled && ssoProviders.value.length > 0
);

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
  <div class="space-y-6" data-testid="auth-standard-section">
    <!-- SSO-only mode: render only SSO provider buttons -->
    <template v-if="showSsoOnly">
      <div class="space-y-3" data-testid="auth-sso-only-section">
        <SsoButton
          v-for="provider in ssoProviders"
          :key="provider.route_name"
          :route-name="provider.route_name"
          :display-name="provider.display_name" />
      </div>
    </template>

    <!-- Standard auth mode: password/passwordless forms with optional SSO -->
    <template v-else>
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

      <!-- SSO section when SSO is enabled -->
      <template v-if="ssoEnabled && ssoProviders.length > 0">
        <!-- Divider -->
        <div class="relative" data-testid="auth-sso-divider">
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
    </template>
  </div>
</template>
