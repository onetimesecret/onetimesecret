<script setup lang="ts">
import type { LayoutProps } from '@/types/ui/layouts';
import { useProductIdentity } from '@/stores/identityStore';

const productIdentity = useProductIdentity();

withDefaults(defineProps<LayoutProps>(), {
  displayMasthead: true,
  displayNavigation: true,
  colonel: false,
});


</script>

<template>
  <header class="bg-white dark:bg-gray-900">
    <div class="container mx-auto min-w-[320px] max-w-2xl p-4">
    <label
      class="block cursor-pointer"
      for="logo-upload"
      role="button"
      aria-label="Upload logo"
      aria-describedby="logoHelp">
      <div
        :class="{
          [productIdentity.cornerClass]: true,
        }"
        class="hover:ring-primary-500 flex size-14 items-center justify-center overflow-hidden bg-gray-100 hover:ring-2 hover:ring-offset-2 dark:bg-gray-700 sm:size-16">
        <img
          :src="productIdentity.logoUri"
          alt="Logo"
          class="size-16 object-contain"
          :class="{
            [productIdentity.cornerClass]: true,
          }"
        />
        <svg
          class="size-8 text-gray-400 dark:text-gray-500"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
          />
        </svg>
      </div>
    </label>
    </div>
  </header>
</template>
