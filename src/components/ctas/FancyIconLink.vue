<!-- src/components/ctas/FancyIconLink.vue -->

<script setup lang="ts">
  import { computed, ref } from 'vue';
  import FancyIcon from '@/components/ctas/FancyIcon.vue';
  import UpgradeIdentityModal from '@/components/modals/UpgradeIdentityModal.vue';

  defineProps<{
    ariaLabel?: string;
    to: string;
    colonel?: boolean;
  }>();

  const showUpgradeNudge = computed(() => {
    // Logic to determine if the user should see the upgrade nudge
    // For example, check if the user is on a free plan
    //return !cust.value.isPremium
    return true;
  });

  const isUpgradeModalOpen = ref(false);

  const openUpgradeModal = () => {
    isUpgradeModalOpen.value = true;
  };

  const closeUpgradeModal = () => {
    isUpgradeModalOpen.value = false;
  };

  const handleUpgrade = () => {
    // Handle any additional logic here when the user has clicked the upgrade button.
  };
</script>

<template>
  <div class="container">
    <div
      class="group ml-2 inline-flex items-center space-x-2 text-sm font-medium
        text-gray-700 transition-colors
        duration-150 ease-in-out hover:text-brand-500 focus:outline-none
        focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
        dark:text-gray-300 dark:hover:text-brand-400 dark:focus:ring-offset-gray-900">
      <button
        v-if="showUpgradeNudge"
        @click="openUpgradeModal">
        <FancyIcon />
      </button>
    </div>

    <UpgradeIdentityModal
      :is-open="isUpgradeModalOpen"
      to="/plans/identity"
      @close="closeUpgradeModal"
      @upgrade="handleUpgrade" />
  </div>
</template>

<style scoped>
  @media (prefers-reduced-motion: reduce) {
    svg,
    svg * {
      animation: none !important;
    }
  }
</style>
