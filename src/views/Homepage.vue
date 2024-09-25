<script setup lang="ts">
import SecretForm from '@/components/SecretForm.vue';
import HomepagePlansCTA from '@/components/ctas/HomepagePlansCTA.vue';
import HomepageTaglines from '@/components/HomepageTaglines.vue';

const authenticated = window.authenticated;
const authenticationSettings = window.authentication;

const shrimp = window.shrimp;
</script>

<template>

  <HomepageTaglines v-if="!authenticated" />

  <HomepagePlansCTA v-if="authenticationSettings.signup" />

  <SecretForm :shrimp="shrimp"
              :withRecipient="false"
              :withAsterisk="true"
              :withGenerate="true" />

  <div v-if="!authenticated"
       class="flex flex-col items-center text-center my-6">
    <p class="text-sm text-gray-400 italic dark:text-gray-400 mb-4">{{ $t('web.homepage.secret_hint') }}</p>
  </div>

</template>
