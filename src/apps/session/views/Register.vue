<!-- src/views/auth/Signup.vue -->
<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import AlternateSignUpMethods from '@/apps/session/components/AlternateSignUpMethods.vue';
  import AuthView from '@/apps/session/components/AuthView.vue';
  import SignUpForm from '@/apps/session/components/SignUpForm.vue';
  import { useJurisdictionStore } from '@/shared/stores/jurisdictionStore';
  import { useLanguageStore } from '@/shared/stores/languageStore';
  import { storeToRefs } from 'pinia';
  import { computed } from 'vue';
  const { t } = useI18n();

  const jurisdictionStore = useJurisdictionStore();
  const { getCurrentJurisdiction } = storeToRefs(jurisdictionStore);

  const languageStore = useLanguageStore();
  const currentJurisdiction = computed(
    () =>
      getCurrentJurisdiction.value || {
        identifier: t('unknown-jurisdiction'),
        display_name: t('unknown-jurisdiction'),
        domain: '',
        icon: {
          collection: 'mdi',
          name: 'help-circle',
        },
        enabled: false,
      }
  );

  const alternateProviders = [
    { name: t('google'), icon: 'mdi-google' },
    { name: 'GitHub', icon: 'mdi-github' },
  ];
</script>

<template>
  <AuthView
    :heading="t('web.signup.create-your-account')"
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
        to="/signin"
        class="font-medium text-brand-600 underline transition-colors duration-200 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
        {{ t('web.signup.have_an_account') }}
      </router-link>
    </template>
  </AuthView>
</template>
