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

    <template>
      <!-- Upgrade Modal -->
      <teleport to="body">
        <!-- Background overlay -->
        <div v-if="isUpgradeModalOpen"
            @click="handleBackdropClick"
            @touchend="handleBackdropInteraction"
             class="fixed inset-0 z-50 overflow-y-auto bg-gray-900 bg-opacity-50 dark:bg-opacity-80"
             aria-labelledby="modal-title"
             role="dialog"
             aria-modal="true">

          <!-- Modal content -->
          <div id="upgrade-modal"
               class="flex items-end justify-center min-h-screen px-4 pt-4 pb-20 text-center sm:block sm:p-0">

            <!-- Modal panel -->

            <div @click="handleModalClick"
                @touchend="handleModalInteraction"
                 class="inline-block w-full max-w-md p-6 my-56 overflow-hidden text-left align-middle transition-all transform
                 bg-white shadow-xl rounded-2xl dark:bg-gray-800 sm:max-w-lg">
              <div class="sm:flex sm:items-start">
                <div
                     class="flex items-center justify-center flex-shrink-0 w-12 h-12 mx-auto
                     bg-brandcomp-100 rounded-full sm:mx-0 sm:h-10 sm:w-10 dark:bg-brandcomp-900">
                  <svg class="w-6 h-6 text-brandcomp-600 dark:text-brandcomp-300"
                       fill="none"
                       stroke="currentColor"
                       viewBox="0 0 24 24"
                       xmlns="http://www.w3.org/2000/svg">
                    <path stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M5 13l4 4L19 7"></path>
                  </svg>
                </div>
                <div class="mt-3 text-center sm:mt-0 sm:ml-4 sm:text-left">
                  <h3 class="text-lg font-medium leading-6 text-gray-900 dark:text-white"
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

              <!-- Additional content to make the modal taller -->
              <div class="mt-6 space-y-4">
                <h4 class="text-md font-semibold text-gray-700 dark:text-gray-200">Benefits of Custom Domains:</h4>
                <ul class="list-disc list-inside text-sm text-gray-600 dark:text-gray-300 space-y-2">
                  <li>Improved brand recognition</li>
                  <li>Enhanced SEO performance</li>
                  <li>Increased user trust and credibility</li>
                  <li>Full control over your online presence</li>
                </ul>
                <p class="text-sm text-gray-500 dark:text-gray-400 italic">
                  "Using a custom domain increased our conversion rates by 25%!" - Happy Customer
                </p>
              </div>

              <div class="mt-6 sm:mt-4 sm:flex sm:flex-row-reverse">
                <button @click="upgradeAccount"
                        type="button"
                        class="w-full px-4 py-2 text-base font-medium text-white bg-brandcomp-600 border border-transparent rounded-md shadow-sm hover:bg-brandcomp-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brandcomp-500 sm:w-auto sm:text-sm dark:bg-brandcomp-500 dark:hover:bg-brandcomp-600"
                        aria-label="Upgrade account">
                  Upgrade Now
                </button>
                <div class="mt-3 sm:mt-0 sm:mr-3">
                  <button @click="closeUpgradeModal"
                          type="button"
                          class="w-full px-4 py-2 text-base font-medium text-gray-700 bg-white border border-gray-300 rounded-md shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brandcomp-500 sm:w-auto sm:text-sm dark:bg-gray-700 dark:text-white dark:hover:bg-gray-600 dark:border-gray-600"
                          aria-label="Close modal">
                    Maybe Later
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </teleport>
    </template>

  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue';

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
  // Implement your upgrade logic here
  closeUpgradeModal()
}

const handleBackdropClick = () => {
  closeUpgradeModal()
}

const handleModalClick = (event: Event) => {
  event.stopPropagation()
}

const handleBackdropInteraction = (event: Event) => {
  if (event.type === 'touchend') {
    event.preventDefault() // Prevent the following click event
  }
  closeUpgradeModal()
}

const handleModalInteraction = (event: Event) => {
  event.stopPropagation()
}

const handleEscapeKey = (event: KeyboardEvent) => {
  if (event.key === 'Escape') {
    closeUpgradeModal()
  }
}

onMounted(() => {
  document.addEventListener('keydown', handleEscapeKey)
})

onUnmounted(() => {
  document.removeEventListener('keydown', handleEscapeKey)
})
</script>


<style scoped>
@media (prefers-reduced-motion: reduce) {

  svg,
  svg * {
    animation: none !important;
  }
}
</style>
