<!-- eslint-disable vue/multi-word-component-names -->
<!-- src/views/auth/Signin.vue -->
<script setup lang="ts">
import AuthView from '@/components/auth/AuthView.vue';
import AuthMethodSelector from '@/components/auth/AuthMethodSelector.vue';
import { useLanguageStore } from '@/stores/languageStore';

const { t } = useI18n();

const languageStore = useLanguageStore();
</script>

<template>
  <AuthView
    :heading="t('sign-in-to-your-account')"
    heading-id="signin-heading"
    :with-subheading="true"
    :hide-icon="true"
    :hide-background-icon="false">
    <template #form>
      <AuthMethodSelector
        :locale="languageStore.currentLocale ?? ''" />
    </template>
    <template #footer>
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
  </AuthView>
</template>
