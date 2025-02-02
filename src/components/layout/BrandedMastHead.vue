<!-- src/components/layout/Masthead.vue -->
<script setup lang="ts">
  import type { LayoutProps } from '@/types/ui/layouts';
  import { useProductIdentity } from '@/stores/identityStore';
  import { ref } from 'vue';

  const productIdentity = useProductIdentity();
  const imageError = ref(false);

  const handleImageError = () => {
    imageError.value = true;
  };

  interface Props extends LayoutProps {
    headertext: string;
    subtext: string;
  }

  withDefaults(defineProps<Props>(), {
    displayMasthead: true,
    displayNavigation: true,
    headertext: 'secure-links',
    subtext: 'a-trusted-way-to-share-sensitive-information-that-self-destructs-after-being-viewed',
  });
</script>

<template>
  <div class="bg-white dark:bg-gray-900 py-8 transition-colors duration-200">
    <div class="container mx-auto px-4 max-w-2xl">
      <div class="flex flex-col items-center gap-8">
        <!-- Logo Section -->
        <div
          class="relative"
          role="region"
          aria-label="$t('brand-logo')">
          <router-link to="/">
            <div
              :class="[
                productIdentity.cornerClass,
                'flex size-16 items-center justify-center overflow-hidden bg-gray-100 dark:bg-gray-800 transition-all duration-200',
              ]">
              <img
                v-if="productIdentity.logoUri && !imageError"
                :src="productIdentity.logoUri"
                alt="$t('company-logo')"
                class="size-16 object-contain"
                :class="productIdentity.cornerClass"
                @error="handleImageError" />
              <!-- Updated placeholder icon to match SecretPreview -->
              <svg
                v-else
                class="size-8 text-gray-400 dark:text-gray-500"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
              </svg>
            </div>
          </router-link>
        </div>

        <!-- Content Section -->
        <div
          class="text-center space-y-3"
          :class="productIdentity.fontFamilyClass"
          >
          <h1
            class="text-2xl sm:text-3xl font-medium text-gray-900 dark:text-gray-100"
            :class="productIdentity.fontFamilyClass">
            {{ $t(headertext) }}
          </h1>
          <p
            class="text-sm sm:text-base text-gray-600 dark:text-gray-300 max-w-md mx-auto">
            {{ $t(subtext) }}
          </p>
        </div>
      </div>
    </div>
  </div>
</template>
