<script setup lang="ts">
import SecretForm from '@/components/SecretForm.vue';
import HomepagePlansCTA from '@/components/ctas/HomepagePlansCTA.vue';

const authenticated = window.authenticated;
const authenticationSettings = window.authentication;

const shrimp = window.shrimp;
</script>

<template>

    <div v-if="!authenticated"
         class="flex flex-col items-center text-center">
        <h3 class="font-base mb-2 sm:mx-12 md:mx-2 text-gray-600 dark:text-gray-100 sm:block">
            {{ $t('web.homepage.tagline1') }}
        </h3>
        <p class="mb-6 mx-12 sm:mx-2 text-base text-gray-400 dark:text-gray-400 italic">
            {{ $t('web.homepage.tagline2') }}
        </p>
    </div>

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
