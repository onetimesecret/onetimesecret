<template>
  <div class="hidden sm:flex items-center">
    <router-link to="/"
                 class="text-gray-400 hover:text-gray-300 transition group">
      <span id="userEmail"
            :class="{ 'animate-pulse': isNewFeature }"
            class="group-hover:text-gray-300">
        {{ cust.custid }}
      </span>

    </router-link>
    <button v-if="showUpgradeNudge"
          @click="openUpgradeModal">
        <FancyIcon
          ariaLabel="Click this lightning bolt to upgrade for custom domains"
                       class="ml-2 text-gray-500 hover:text-gray-400 transition" />
                      </button>
    <router-link v-if="colonel"
                 to="/colonel/"
                 title=""
                 class="ml-2 text-gray-400 hover:text-gray-300 transition">
      <Icon icon="mdi:star"
            class="w-4 h-4" />
    </router-link>
    <span class="mx-2 text-gray-400">|</span>
  </div>

  <!-- Upgrade Modal -->
  <teleport to="body">
    <div v-if="isUpgradeModalOpen"
         class="fixed z-10 inset-0 overflow-y-auto"
         aria-labelledby="modal-title"
         role="dialog"
         aria-modal="true">
      <!-- Modal content -->
      <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
        <!-- Background overlay -->
        <div class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"
             aria-hidden="true"></div>

        <!-- Modal panel -->
        <div
             class="inline-block align-bottom bg-white dark:bg-gray-800 rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full">
          <div class="bg-white dark:bg-gray-800 px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
            <div class="sm:flex sm:items-start">
              <div class="mt-3 text-center sm:mt-0 sm:ml-4 sm:text-left">
                <h3 class="text-lg leading-6 font-medium text-gray-900 dark:text-white"
                    id="modal-title">
                  Upgrade to Custom Domains
                </h3>
                <div class="mt-2">
                  <p class="text-sm text-gray-500 dark:text-gray-300">
                    Boost your brand identity and build trust with your users by using your own custom domain.
                  </p>
                </div>
              </div>
            </div>
          </div>
          <div class="bg-gray-50 dark:bg-gray-700 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
            <button @click="upgradeAccount"
                    type="button"
                    class="w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-indigo-600 text-base font-medium text-white hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:ml-3 sm:w-auto sm:text-sm dark:bg-indigo-500 dark:hover:bg-indigo-600">
              Upgrade Now
            </button>
            <button @click="closeUpgradeModal"
                    type="button"
                    class="mt-3 w-full inline-flex justify-center rounded-md border border-gray-300 shadow-sm px-4 py-2 bg-white text-base font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:mt-0 sm:ml-3 sm:w-auto sm:text-sm dark:bg-gray-600 dark:text-white dark:hover:bg-gray-500 dark:border-gray-500">
              Maybe Later
            </button>
          </div>
        </div>
      </div>
    </div>
  </teleport>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue'
import FancyIcon from '@/components/ctas/FancyIcon.vue';

import { Icon } from '@iconify/vue';
import { Customer } from '@/types/onetime';

defineProps<{
  cust: Customer;
  colonel?: boolean;

}>();

const showUpgradeNudge = computed(() => {
  // Logic to determine if the user should see the upgrade nudge
  // For example, check if the user is on a free plan
  //return !cust.value.isPremium
  return true;
})
const isNewFeature = ref(false) // Set to false after user has seen it once
const isUpgradeModalOpen = ref(false)

const openUpgradeModal = () => {
  isUpgradeModalOpen.value = true
  isNewFeature.value = false
}

const closeUpgradeModal = () => {
  isUpgradeModalOpen.value = false
}

const upgradeAccount = () => {
  // Logic to handle account upgrade
  console.log('Upgrading account...')
  closeUpgradeModal()
}
</script>

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
  animation: pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
}
</style>
