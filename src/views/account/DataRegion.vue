<!-- src/views/account/DataRegion.vue -->

<script setup lang="ts">
  import { onMounted } from 'vue';
  import { useRouter } from 'vue-router';

  const router = useRouter();

  onMounted(() => {
    // Redirect to the current region view by default
    router.replace('/account/region/current');
  });
</script>

<template>
  <div></div>
</template>
