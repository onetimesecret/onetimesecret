<script setup lang="ts">
import { useWindowProps } from '@/composables/useWindowProps';
import CreateInboundSecret from '@/components/secrets/CreateInboundSecret.vue';
import HomepageTaglines from '@/components/HomepageTaglines.vue';

const { authenticated } = useWindowProps(['authenticated']);

</script>

<template>
  <div class="bg-white dark:bg-gray-800 shadow-md rounded-lg p-6">
    <HomepageTaglines v-if="authenticated" />

    <CreateInboundSecret />
  </div>
</template>
