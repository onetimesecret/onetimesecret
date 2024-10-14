<template>
  <div class="container">
    <div class="group inline-flex items-center space-x-2 text-sm font-medium ml-2
        text-gray-700 hover:text-brand-500
        focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
        dark:text-gray-300 dark:hover:text-brand-400 dark:focus:ring-offset-gray-900
        transition-colors duration-150 ease-in-out">

      <button v-if="showUpgradeNudge"
              @click="openUpgradeModal">
        <svg xmlns="http://www.w3.org/2000/svg"
             class="h-5 w-5 transition-transform group-hover:scale-110"
             width="20"
             height="20"
             viewBox="0 0 20 20"
             fill="none">
          <defs>
            <linearGradient id="offKilterGradient"
                            x1="0%"
                            y1="0%"
                            x2="100%"
                            y2="100%">
              <stop offset="0%"
                    stop-color="#EC4899">
                <animate attributeName="stop-color"
                         values="#EC4899; #A855F7; #EAB308; #EC4899"
                         dur="7s"
                         repeatCount="indefinite" />
              </stop>
              <stop offset="100%"
                    stop-color="#EAB308">
                <animate attributeName="stop-color"
                         values="#EAB308; #EC4899; #A855F7; #EAB308"
                         dur="5s"
                         repeatCount="indefinite" />
              </stop>
            </linearGradient>
          </defs>
          <path fill-rule="evenodd"
                d="M11.3 1.046A1 1 0 0112 2v5h4a1 1 0 01.82 1.573l-7 10A1 1 0 018 18v-5H4a1 1 0 01-.82-1.573l7-10a1 1 0 011.12-.38z"
                clip-rule="evenodd"
                fill="url(#offKilterGradient)">
            <animate attributeName="d"
                     values="M11.3 1.046A1 1 0 0112 2v5h4a1 1 0 01.82 1.573l-7 10A1 1 0 018 18v-5H4a1 1 0 01-.82-1.573l7-10a1 1 0 011.12-.38z;
              M11.1 1.246A1 1 0 0112 2.2v4.8h4a1 1 0 01.82 1.573l-7.2 9.8A1 1 0 018 18v-5H3.8a1 1 0 01-.82-1.573l7.2-9.8a1 1 0 01.92-.381z;
              M11.3 1.046A1 1 0 0112 2v5h4a1 1 0 01.82 1.573l-7 10A1 1 0 018 18v-5H4a1 1 0 01-.82-1.573l7-10a1 1 0 011.12-.38z"
                     dur="10s"
                     repeatCount="indefinite" />
          </path>
        </svg>
      </button>
    </div>

    <UpgradeIdentityModal
      :is-open="isUpgradeModalOpen"
      to="/plans/identity"
      @close="closeUpgradeModal"
      @upgrade="handleUpgrade"
    />

  </div>
</template>

<script setup lang="ts">
import UpgradeIdentityModal from '@/components/modals/UpgradeIdentityModal.vue';
import { computed, ref } from 'vue';

defineProps<{
  ariaLabel: string;
  to: string;
  colonel?: boolean;
}>();

const showUpgradeNudge = computed(() => {
  // Logic to determine if the user should see the upgrade nudge
  // For example, check if the user is on a free plan
  //return !cust.value.isPremium
  return true;
})

const isUpgradeModalOpen = ref(false)

const openUpgradeModal = () => {
  isUpgradeModalOpen.value = true
}

const closeUpgradeModal = () => {
  isUpgradeModalOpen.value = false
}

const handleUpgrade = () => {
  // Handle any additional logic here when the user has clicked the upgrade button.
};

</script>


<style scoped>
@media (prefers-reduced-motion: reduce) {

  svg,
  svg * {
    animation: none !important;
  }
}
</style>
