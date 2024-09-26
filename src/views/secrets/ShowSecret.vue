<!-- eslint-disable vue/multi-word-component-names -->
<script setup lang="ts">
import { defineProps } from 'vue'
import UnknownSecret from './UnknownSecret.vue';

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
