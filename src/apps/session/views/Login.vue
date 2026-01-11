<!-- src/apps/session/views/Login.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import AuthMethodSelector from '@/apps/session/components/AuthMethodSelector.vue';
import AuthView from '@/apps/session/components/AuthView.vue';
import { useLanguageStore } from '@/shared/stores/languageStore';
import { isMagicLinksEnabled } from '@/utils/features';
import { ref, type ComponentPublicInstance } from 'vue';

const { t } = useI18n();

const languageStore = useLanguageStore();
const magicLinksEnabled = isMagicLinksEnabled();

// Reference to AuthMethodSelector (kept for potential future use)
const authMethodSelectorRef = ref<ComponentPublicInstance<{ currentMode: 'passwordless' | 'password' }> | null>(null);

// Mode change handler (kept for potential future use)
const handleModeChange = (_mode: 'passwordless' | 'password') => {
  // Footer is now consistent across modes, no need to track
};
</script>

<template>
  <AuthView
    :heading="t('web.COMMON.login_to_your_account')"
    heading-id="signin-heading"
    :with-subheading="true"
    :hide-icon="false"
    :hide-background-icon="false"
    :show-return-home="false">
    <template #form>
      <AuthMethodSelector
        ref="authMethodSelectorRef"
        :locale="languageStore.currentLocale ?? ''"
        @mode-change="handleModeChange" />
    </template>
    <template #footer>
      <nav
        aria-label="Additional sign-in options"
        class="flex items-center justify-center gap-2 text-sm">
        <!-- Consistent footer for all modes when magic links enabled -->
        <template v-if="magicLinksEnabled">
          <router-link
            to="/help"
            class="text-gray-500 transition-colors duration-200 hover:text-gray-700 hover:underline dark:text-gray-400 dark:hover:text-gray-300">
            {{ t('web.login.need_help') }}
          </router-link>
          <span class="text-gray-300 dark:text-gray-600" aria-hidden="true">&#8226;</span>
          <router-link
            to="/signup"
            class="text-gray-500 transition-colors duration-200 hover:text-gray-700 hover:underline dark:text-gray-400 dark:hover:text-gray-300">
            {{ t('web.login.create_account') }}
          </router-link>
        </template>
        <!-- Password-only mode (magic links disabled): original footer -->
        <template v-else>
          <span class="text-gray-600 dark:text-gray-400">
            {{ t('web.login.alternate_prefix') }}
          </span>
          {{ ' ' }}
          <router-link
            to="/signup"
            class="font-medium text-brand-600 underline transition-colors duration-200 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
            {{ t('web.login.need_an_account') }}
          </router-link>
        </template>
      </nav>
    </template>
  </AuthView>
</template>
