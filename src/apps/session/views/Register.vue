<!-- src/apps/session/views/Register.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import AlternateSignUpMethods from '@/apps/session/components/AlternateSignUpMethods.vue';
  import AuthView from '@/apps/session/components/AuthView.vue';
  import SignUpForm from '@/apps/session/components/SignUpForm.vue';
  import { useJurisdictionDisplayNames } from '@/shared/stores/jurisdictionStore';
  import { useLanguageStore } from '@/shared/stores/languageStore';
  import { computed } from 'vue';
  import { useRoute } from 'vue-router';
  const { t } = useI18n();
  const route = useRoute();

  const { currentJurisdictionWithDisplayName } = useJurisdictionDisplayNames();

  const languageStore = useLanguageStore();
  const currentJurisdiction = computed(() =>
    currentJurisdictionWithDisplayName.value || {
      identifier: t('web.regions.unknown_jurisdiction'),
      display_name_i18n_key: 'web.regions.unknown_jurisdiction',
      display_name: t('web.regions.unknown_jurisdiction'),
      domain: '',
      icon: {
        collection: 'mdi',
        name: 'help-circle',
      },
      enabled: false,
    }
  );

  const alternateProviders = [
    { name: t('web.auth.google'), icon: 'mdi-google' },
    { name: 'GitHub', icon: 'mdi-github' },
  ];

  // Build signin link with preserved query params (email, redirect, product, interval)
  const signinLink = computed(() => {
    const query: Record<string, string> = {};
    const preserveParams = ['email', 'redirect', 'product', 'interval'];

    for (const param of preserveParams) {
      if (typeof route.query[param] === 'string') {
        query[param] = route.query[param];
      }
    }

    return Object.keys(query).length > 0 ? { path: '/signin', query } : '/signin';
  });
</script>

<template>
  <AuthView
    :heading="t('web.signup.create_your_account')"
    heading-id="signup-heading"
    :with-heading="true"
    :with-subheading="true"
    :hide-icon="false"
    :hide-background-icon="true">
    <template #form>
      <SignUpForm
        :locale="languageStore.currentLocale ?? ''"
        :jurisdiction="currentJurisdiction" />
      <AlternateSignUpMethods
        :alternate-providers="alternateProviders"
        class="hidden" />
    </template>
    <template #footer>
      <span class="text-gray-600 dark:text-gray-400">
        {{ t('web.signup.alternate_prefix') }}
      </span>
      {{ ' ' }}
      <router-link
        :to="signinLink"
        class="font-medium text-brand-600 underline transition-colors duration-200 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
        {{ t('web.signup.have_an_account') }}
      </router-link>
    </template>
  </AuthView>
</template>
