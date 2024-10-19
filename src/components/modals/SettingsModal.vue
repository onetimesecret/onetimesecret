<template>
  <div v-if="isOpen"
       class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 backdrop-blur-sm"
       aria-labelledby="settings-modal"
       role="dialog"
       aria-modal="true">
    <div ref="modalContentRef"
         class="relative mx-auto w-full max-w-lg overflow-hidden rounded-2xl bg-white shadow-2xl dark:bg-gray-800 transition-all duration-300 ease-out transform">
      <div class="flex h-[90vh] sm:h-[80vh] flex-col">
        <!-- Modal Header -->
        <div class="flex-shrink-0 flex items-center justify-between border-b p-4 border-gray-200 dark:border-gray-700">
          <h2 id="settings-modal" class="text-2xl font-bold text-gray-900 dark:text-white">
            Settings
          </h2>
          <button @click="closeModal"
                  class="text-gray-400 hover:text-gray-500 dark:text-gray-300 dark:hover:text-gray-200 transition-colors duration-200"
                  aria-label="Close settings">
            <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <!-- Tabs -->
        <div class="flex-shrink-0 flex overflow-x-auto border-b border-gray-200 dark:border-gray-700">
          <button v-for="tab in tabs"
                  :key="tab"
                  @click="activeTab = tab"
                  class="px-4 py-2 text-sm sm:text-base font-medium transition-colors duration-200 whitespace-nowrap"
                  :class="[activeTab === tab ? 'border-b-2 border-brand-600 text-brand-600' : 'text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200']">
            {{ tab }}
          </button>
        </div>

        <!-- Content -->
        <div class="flex-grow overflow-y-auto p-4 sm:p-6">
          <!-- General Tab -->
          <div v-if="activeTab === 'General'" class="space-y-8">
            <section>
              <h3 class="text-lg font-semibold text-gray-900 dark:text-white mb-4">Appearance</h3>
              <div class="flex items-center justify-between">
                <span class="text-gray-700 dark:text-gray-300">Theme</span>
                <ThemeToggle />
              </div>
            </section>

            <section>
              <h3 class="text-lg font-semibold text-gray-900 dark:text-white mb-4">Language</h3>
              <LanguageToggle @menuToggled="handleMenuToggled" />
            </section>

            <section>
              <h3 class="text-lg font-semibold text-gray-900 dark:text-white mb-4">Jurisdiction ({{ cust?.custid }})</h3>
              <div class="rounded-lg bg-gray-100 p-4 dark:bg-gray-700 prose dark:prose-invert">
                <p class="text-sm sm:text-base text-gray-600 dark:text-gray-300">
                  Your data for this account is located in the
                  <span class="font-semibold">{{ currentJurisdiction.display_name }}</span>.<br>
                  This is determined by the domain you're accessing:
                  <span class="underline">{{ currentJurisdiction.domain }}.</span>
                </p>
              </div>
              <MoreInfoText textColor="text-brandcomp-800 dark:text-gray-100"
                            bgColor="bg-white dark:bg-gray-800">
                <div class="px-4 py-4 sm:px-6 sm:py-6">
                  <div class="max-w-xl text-sm sm:text-base text-gray-600 dark:text-gray-300 prose dark:prose-invert">
                    <p>
                      Accounts in each location are completely separate with no data shared between them.
                      You can create an account with the same email address in more than one location.
                    </p>
                    <p>
                      To learn more, please <a :href="`${supportHost}/docs`" class="text-brand-600 hover:underline">visit our documentation</a> or
                      <RouterLink to="/feedback" class="text-brand-600 hover:underline">contact us</RouterLink>.
                    </p>
                  </div>
                </div>
              </MoreInfoText>
              <div class="mt-6">
                <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Available Jurisdictions:</h4>
                <ul class="space-y-2">
                  <li v-for="jurisdiction in jurisdictions"
                      :key="jurisdiction.identifier"
                      class="flex items-center space-x-2 text-sm">
                    <Icon :icon="jurisdiction.icon" class="h-5 w-5" aria-hidden="true" />
                    <a :href="`https://${jurisdiction.domain}/signup`"
                       :class="{ 'font-semibold': currentJurisdiction.identifier === jurisdiction.identifier }"
                       class="text-gray-600 dark:text-gray-300 hover:text-brand-600 dark:hover:text-brand-400">
                      {{ jurisdiction.display_name }}
                    </a>
                    <span v-if="currentJurisdiction.identifier === jurisdiction.identifier"
                          class="text-xs text-gray-500 dark:text-gray-400">(Current)</span>
                  </li>
                </ul>
              </div>
            </section>
          </div>
        </div>

        <!-- Footer -->
        <div class="flex-shrink-0 flex justify-end bg-gray-50 p-4 dark:bg-gray-700">
          <button @click="closeModal"
                  class="rounded-md bg-brand-600 px-4 py-2 text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 transition-colors duration-200">
            Done
          </button>
        </div>
      </div>
    </div>
  </div>
</template>



<script setup lang="ts">
import LanguageToggle from '@/components/LanguageToggle.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import { useClickOutside } from '@/composables/useClickOutside';
import { useWindowProp } from '@/composables/useWindowProps';
import { useJurisdictionStore } from '@/stores/jurisdictionStore';
import { Icon } from '@iconify/vue';
import { computed, ref } from 'vue';
import MoreInfoText from '@/components/MoreInfoText.vue';

const cust = useWindowProp('cust');
const supportHost = useWindowProp('support_host');

const jurisdictionStore = useJurisdictionStore();
const currentJurisdiction = computed(() => jurisdictionStore.getCurrentJurisdiction);
const jurisdictions = computed(() => jurisdictionStore.getAllJurisdictions);


defineProps<{
  isOpen: boolean;
}>();

const emit = defineEmits<{
  (e: 'close'): void;
}>();

const modalContentRef = ref<HTMLElement | null>(null);
const tabs = ['General']; // , 'Notifications', 'Security'
const activeTab = ref('General');

const closeModal = () => {
  emit('close');
};

const handleMenuToggled = () => {
  // Handle language menu toggle
};

useClickOutside(modalContentRef, closeModal);
</script>
