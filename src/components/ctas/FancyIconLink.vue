<template>
  <router-link :to="to"
               :aria-label="ariaLabel"
               class="">
    <FancyIcon :ariaLabel="ariaLabel" />
    <span v-if="text">{{ text }}</span>
  </router-link>
</template>

<script setup lang="ts">
import FancyIcon from '@/components/ctas/FancyIcon.vue';

defineProps<{
  text?: string;
  to: string;
  ariaLabel: string;
}>();
</script>
