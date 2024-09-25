<script setup lang="ts">
import { useWindowProps } from '@/composables/useWindowProps';
import CreateInboundSecret from '@/components/secrets/CreateInboundSecret.vue';

const { shrimp, authenticated } = useWindowProps(['shrimp', 'authenticated']);

import HomepageTaglines from '@/components/HomepageTaglines.vue';

</script>


<template>

  <div class="bg-white dark:bg-gray-800 shadow-md rounded-lg p-6">
    <HomepageTaglines v-if="authenticated" />

    <CreateInboundSecret :shrimp="shrimp" />

  </div>

</template>
