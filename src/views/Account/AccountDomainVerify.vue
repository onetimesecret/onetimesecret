<template>
  <main class="container mx-auto px-4 py-8">
    <h1 class="text-3xl font-bold mb-6 dark:text-white">Verify Domain</h1>
    <VerifyDomain :domain="domain" />
  </main>
</template>

<script setup lang="ts">
//import { ref } from 'vue';
//import { useRoute } from 'vue-router';
import VerifyDomain from '@/components/VerifyDomain.vue';
//import { CustomDomain } from '@types/onetime'


//const route = useRoute();
//const domain = ref(route.params.domain as string);


</script>
