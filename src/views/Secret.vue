<script setup lang="ts">
import { defineProps } from 'vue'
import UnknownSecret from './secrets/UnknownSecret.vue';

interface Props {
  secretKey: string;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const props = defineProps<Props>()

</script>

<template>
  <UnknownSecret>

  </UnknownSecret>
</template>
