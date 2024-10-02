<script setup lang="ts">
import SecretForm from '@/components/secrets/form/SecretForm.vue';
import HomepagePlansCTA from '@/components/ctas/HomepagePlansCTA.vue';
import HomepageTaglines from '@/components/HomepageTaglines.vue';

const authenticated = window.authenticated;
const authenticationSettings = window.authentication;

</script>

<template>
  <div class="my-6">
    <HomepageTaglines v-if="!authenticated" class="my-6" />

    <HomepagePlansCTA v-if="authenticationSettings.signup" class="" />

    <SecretForm class=""
                :withRecipient="false"
                :withAsterisk="true"
                :withGenerate="true" />

    <div v-if="!authenticated"
        class="flex flex-col items-center text-center my-6">
      <p class="text-sm text-gray-400 italic dark:text-gray-400 mb-4">{{ $t('web.homepage.secret_hint') }}</p>
    </div>
  </div>
</template>
