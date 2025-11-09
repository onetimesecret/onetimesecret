<!-- src/components/layout/HeaderUserNav.vue -->

<script setup lang="ts">
  import { Customer } from '@/schemas/models';
  import OIcon from '@/components/icons/OIcon.vue';

  defineProps<{
    cust: Customer;
    colonel?: boolean;
  }>();
</script>

<template>
  <div class="hidden items-center sm:flex">
    <router-link
      to="/account"
      class="group text-gray-400 transition hover:text-gray-300">
      <span
        id="userEmail"
        class="group-hover:text-gray-300">
        {{ cust.email }}
      </span>
    </router-link>

    <router-link
      v-if="colonel"
      to="/colonel/"
      title=""
      class="ml-2 text-gray-400 transition hover:text-gray-300">
      <OIcon
        collection="mdi"
        name="star"
        class="size-4 text-brand-400" />
    </router-link>
    <span
      class="ml-2 text-gray-400"
      aria-hidden="true"
      role="separator"
      >|</span
    >
  </div>
</template>

<style>
  @keyframes pulse {
    0%,
    100% {
      opacity: 1;
    }

    50% {
      opacity: 0.5;
    }
  }

  .animate-pulse {
    animation: pulse 4s cubic-bezier(0.4, 0, 0.6, 1) infinite;
  }
</style>
