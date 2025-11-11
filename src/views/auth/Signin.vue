<!-- eslint-disable vue/multi-word-component-names -->
<!-- src/views/auth/Signin.vue -->
<script setup lang="ts">
import AuthView from '@/components/auth/AuthView.vue';
import AuthMethodSelector from '@/components/auth/AuthMethodSelector.vue';
import { useLanguageStore } from '@/stores/languageStore';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

const languageStore = useLanguageStore();
</script>

<template>
  <AuthView
    :heading="t('sign-in-to-your-account')"
    heading-id="signin-heading"
    :with-subheading="true">
    <template #form>
      <AuthMethodSelector
        :locale="languageStore.currentLocale ?? ''" />
    </template>
    <template #footer>
      <router-link
        to="/signup"
        class="text-gray-600 transition-colors duration-200 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300">
        {{ t('web.login.need_an_account') }}
      </router-link>
    </template>
  </AuthView>
</template>
