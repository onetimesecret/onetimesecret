<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl py-1">
    <HomepageTaglines
      v-if="!authenticated"
      class="mb-6"
    />

    <HomepagePlansCTA
      v-if="authenticationSettings.signup"
      class="mb-6"
    />

    <SecretForm
      class="mb-8"
      :with-recipient="false"
      :with-asterisk="true"
      :with-generate="true"
    />

    <div
      v-if="!authenticated"
      class="flex flex-col items-center text-center">
      <p class="text-sm italic text-gray-400 dark:text-gray-400">
        {{ $t('web.homepage.secret_hint') }}
      </p>
    </div>
  </div>
</template>

<script setup lang="ts">
import HomepagePlansCTA from '@/components/ctas/HomepagePlansCTA.vue';
import HomepageTaglines from '@/components/HomepageTaglines.vue';
import SecretForm from '@/components/secrets/form/SecretForm.vue';

const authenticated = window.authenticated;
const authenticationSettings = window.authentication;
</script>
