<template>
  <div class="container">
    <div
        class="group inline-flex items-center space-x-2 text-sm font-medium ml-2
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
                    values="
              M11.3 1.046A1 1 0 0112 2v5h4a1 1 0 01.82 1.573l-7 10A1 1 0 018 18v-5H4a1 1 0 01-.82-1.573l7-10a1 1 0 011.12-.38z;
              M11.1 1.246A1 1 0 0112 2.2v4.8h4a1 1 0 01.82 1.573l-7.2 9.8A1 1 0 018 18v-5H3.8a1 1 0 01-.82-1.573l7.2-9.8a1 1 0 01.92-.381z;
              M11.3 1.046A1 1 0 0112 2v5h4a1 1 0 01.82 1.573l-7 10A1 1 0 018 18v-5H4a1 1 0 01-.82-1.573l7-10a1 1 0 011.12-.38z
            "
                    dur="10s"
                    repeatCount="indefinite" />
          </path>
        </svg>
      </button>
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
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue'

defineProps<{
  ariaLabel: string;
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

const upgradeAccount = () => {
  // Logic to handle account upgrade
  console.log('Upgrading account...')
  closeUpgradeModal()
}
</script>

<style scoped>
@media (prefers-reduced-motion: reduce) {

  svg,
  svg * {
    animation: none !important;
  }
}
.glow-effect {
  background: linear-gradient(90deg, #ff00ff, #00ff00, #0000ff, #ff0000, #ff00ff);
  background-size: 400% 400%;
  animation: gradient 5s ease infinite, glow 1.5s ease-in-out infinite alternate;
  border: 2px solid transparent;
  background-clip: padding-box;
  box-shadow: 0 0 15px rgba(255, 255, 255, 0.5);
}
</style>
