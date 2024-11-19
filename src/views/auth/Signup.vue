<!-- eslint-disable vue/multi-word-component-names -->
<!-- src/views/auth/Signup.vue -->
<template>
  <AuthView heading="Create your account" headingId="signup-heading" :withSubheading="true">
    <template #form>
      <SignUpForm :planid="currentPlanId" :jurisdiction="currentJurisdiction" />
      <AlternateSignUpMethods :alternateProviders="alternateProviders" class="hidden" />
    </template>
    <template #footer>
      <router-link to="/signin"
                   class="font-medium text-brand-600 hover:text-brand-500
                          dark:text-brand-400 dark:hover:text-brand-300
                          transition-colors duration-200">
        {{ $t('web.signup.have_an_account') }}
      </router-link>
    </template>
  </AuthView>
</template>

<script setup lang="ts">
import AlternateSignUpMethods from '@/components/auth/AlternateSignUpMethods.vue';
import AuthView from '@/components/auth/AuthView.vue';
import SignUpForm from '@/components/auth/SignUpForm.vue';
import { useWindowProps } from '@/composables/useWindowProps';
import { useJurisdictionStore } from '@/stores/jurisdictionStore';
import { storeToRefs } from 'pinia';
import { ref, computed } from 'vue';

const jurisdictionStore = useJurisdictionStore();
const { getCurrentJurisdiction } = storeToRefs(jurisdictionStore);

const { default_planid } = useWindowProps(['default_planid']);

const currentPlanId = ref(default_planid);

const currentJurisdiction = computed(() => getCurrentJurisdiction.value || {
  identifier: 'Unknown Jurisdiction',
  display_name: 'Unknown Jurisdiction',
  domain: '',
  icon: 'mdi:help-circle',
});

const alternateProviders = [
  { name: 'Google', icon: 'mdi:google' },
  { name: 'GitHub', icon: 'mdi:github' },
];
</script>
