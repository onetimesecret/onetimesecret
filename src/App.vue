<template>

  <div class="container mx-auto p-4">
    <!--<h1 class="text-2xl font-bold mb-4">Welcome to Vue 3 + Tailwind CSS</h1>-->
    <!-- Add your components here -->
    <GlobalBanner content="Welcome to Onetime Secret" class="" v-if="showBanner" />

    <SecretForm />

    <div><ThemeToggle /></div>
  </div>

</template>

<script setup lang="ts">
  import GlobalBanner from '@/components/GlobalBanner.vue';
  import ThemeToggle from '@/components/ThemeToggle.vue'
  import SecretForm from '@/components/SecretForm.vue';
  import { ref } from 'vue';

  const showBanner = ref(false);

  console.log(window.shrimp)
</script>
