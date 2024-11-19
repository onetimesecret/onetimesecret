<script setup lang="ts">
import HomepageTaglines from '@/components/HomepageTaglines.vue';
import InboundSecretForm from '@/components/secrets/form/InboundSecretForm.vue';
import { useWindowProps } from '@/composables/useWindowProps';

const { authenticated } = useWindowProps(['authenticated']);

</script>

<template>
  <div class="bg-white dark:bg-gray-800 shadow-md rounded-lg p-6">
    <HomepageTaglines v-if="authenticated" />

    <InboundSecretForm :enabled="true" title="Support Details" />
  </div>
</template>
