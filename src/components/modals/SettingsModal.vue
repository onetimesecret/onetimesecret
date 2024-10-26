<template>
  <div v-show="isOpen"
       class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/50 backdrop-blur-sm transition-opacity duration-300"
       :class="{ 'opacity-0': !isOpen }"
       aria-labelledby="settings-modal"
       role="dialog"
       aria-modal="true">
    <div ref="modalContentRef"
         class="relative mx-auto w-full max-w-lg overflow-hidden rounded-2xl bg-white shadow-2xl dark:bg-gray-800 transition-all duration-300 ease-out transform"
         :class="{ 'opacity-0 scale-95': !isOpen, 'opacity-100 scale-100': isOpen }">

      <div class="flex h-[90vh] sm:h-[80vh] flex-col">
        <!-- Modal Header -->
        <div class="flex-shrink-0 flex items-center justify-between bg-gray-50 p-4 dark:bg-gray-700">
          <h2 id="settings-modal"
              class="text-2xl font-bold text-gray-900 dark:text-white">
            Settings
          </h2>
          <button @click="closeModal"
                  class="rounded-md p-2 text-gray-500 hover:bg-gray-200 dark:text-gray-300 dark:hover:bg-gray-600 transition-colors duration-200"
                  aria-label="Close settings">
            <svg class="h-5 w-5"
                 fill="none"
                 viewBox="0 0 24 24"
                 stroke="currentColor">
              <path stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <!-- Tabs -->
        <div class="flex-shrink-0 flex overflow-x-auto px-6 py-2 gap-2">
          <button v-for="tab in tabs"
                  :key="tab"
                  @click="activeTab = tab"
                  class="min-w-[80px] px-3 py-1.5 text-base font-medium transition-colors duration-200 whitespace-nowrap rounded-md"
                  :class="[
                    activeTab === tab
              ? 'bg-brand-50 text-brand-600 dark:bg-brand-900/20 dark:text-brand-400'
              : 'text-gray-600 hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-700'
          ]">
            {{ tab }}
          </button>
        </div>

        <!-- Content -->
        <div class="flex-grow overflow-y-auto p-4 sm:p-6">
          <Suspense>
            <template #default>
              <!-- General Tab -->
              <div v-if="activeTab === 'General'"
                   class="space-y-8">
                <section class="space-y-4 pb-6 border-b border-gray-200 dark:border-gray-700"
                         aria-labelledby="appearance-heading">
                  <h3 id="appearance-heading"
                      class="text-lg font-semibold text-gray-900 dark:text-white">
                    Appearance
                  </h3>
                  <div class="rounded-lg bg-gray-50 dark:bg-gray-800 p-4">
                    <button @click="$refs.themeToggle.$el.querySelector('button').click()"
                            class="w-full flex items-center justify-between gap-4 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors duration-200 rounded p-2"
                            :aria-label="`Switch theme`">
                      <div class="flex items-center gap-2">
                        <Icon icon="carbon:light-filled"
                              class="h-5 w-5 text-gray-500 dark:text-gray-400"
                              aria-hidden="true" />
                        <span class="text-sm font-medium text-gray-700 dark:text-gray-300">
                          Theme
                        </span>
                      </div>
                      <ThemeToggle ref="themeToggle"
                                   @theme-changed="handleThemeChange" />
                    </button>
                  </div>
                </section>

                <section class="space-y-4 pb-6 border-b border-gray-200 dark:border-gray-700"
                         aria-labelledby="language-heading">
                  <h3 id="language-heading"
                      class="text-lg font-semibold text-gray-900 dark:text-white">
                    Language
                  </h3>
                  <div class="rounded-lg bg-gray-50 dark:bg-gray-800 p-4">
                    <LanguageToggle @menuToggled="handleMenuToggled"
                                    class="w-full" />
                  </div>
                </section>

                <section class="space-y-6"
                         aria-labelledby="jurisdiction-heading">
                  <header class="flex flex-col space-y-1">
                    <h3 id="jurisdiction-heading"
                        class="text-lg font-semibold text-gray-900 dark:text-white">
                      Jurisdiction
                    </h3>
                    <p v-if="cust?.custid"
                       class="text-sm text-gray-500 dark:text-gray-400">
                      Account ID: {{ cust.custid }}
                    </p>
                  </header>

                  <div class="rounded-lg bg-gray-50 p-6 dark:bg-gray-800 prose prose-base dark:prose-invert max-w-none">
                    <div class="space-y-4">
                      <div class="flex items-center gap-2">
                        <Icon :icon="currentJurisdiction.icon"
                              class="h-5 w-5 flex-shrink-0"
                              aria-hidden="true" />
                        <p class="text-gray-700  dark:text-gray-200 m-0">
                          Your data for this account is located in the
                          <strong class="font-medium">{{ currentJurisdiction.display_name }}</strong>
                        </p>
                      </div>

                      <p class="text-gray-600 dark:text-gray-300 m-0">
                        This is determined by the domain you're accessing:
                        <span class="px-2 py-1 bg-gray-100 dark:bg-gray-700 rounded text-base">
                          {{ currentJurisdiction.domain }}
                        </span>
                      </p>

                      <div class="space-y-2">
                        <p class="text-gray-600 dark:text-gray-300 m-0">
                          Accounts in each location are completely separate with no data shared between them.
                          You can create an account with the same email address in more than one location.
                        </p>

                        <p class="text-gray-600 dark:text-gray-300 m-0">
                          To learn more, please
                          <a :href="`${supportHost}/docs`"
                             class="text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300 font-medium"
                             target="_blank"
                             rel="noopener">
                            visit our documentation
                          </a>
                          or
                          <RouterLink to="/feedback"
                                      class="text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300 font-medium">
                            contact us
                          </RouterLink>.
                        </p>
                      </div>
                    </div>
                  </div>

                  <div class="space-y-3">
                    <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300">
                      Available Jurisdictions
                    </h4>

                    <ul
                        class="divide-y divide-gray-100 dark:divide-gray-700 rounded-lg border border-gray-200 dark:border-gray-700">
                      <li v-for="jurisdiction in jurisdictions"
                          :key="jurisdiction.identifier"
                          class="flex items-center gap-3 p-3 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors">
                        <Icon :icon="jurisdiction.icon"
                              class="h-5 w-5 flex-shrink-0 text-gray-400 dark:text-gray-500"
                              aria-hidden="true" />

                        <a :href="`https://${jurisdiction.domain}/signup`"
                           :class="{
                            'font-medium': currentJurisdiction.identifier === jurisdiction.identifier
                          }"
                           class="flex-grow text-gray-700 dark:text-gray-200 hover:text-brand-600
                 dark:hover:text-brand-400 text-sm">
                          {{ jurisdiction.display_name }}
                        </a>

                        <span v-if="currentJurisdiction.identifier === jurisdiction.identifier"
                              class="inline-flex items-center rounded-full bg-brand-50 dark:bg-brand-900/20
                 px-2 py-1 text-xs font-medium text-brand-700 dark:text-brand-300"
                              aria-label="Current jurisdiction">
                          Current
                        </span>
                      </li>
                    </ul>
                  </div>
                </section>



              </div>
            </template>
            <template #fallback>
              <div class="flex items-center justify-center h-full">
                <div class="animate-spin rounded-full h-8 w-8 border-t-2 border-b-2 border-brand-600"></div>
              </div>
            </template>
          </Suspense>
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
import { useWindowProp } from '@/composables/useWindowProps';
import { useJurisdictionStore } from '@/stores/jurisdictionStore';
import { Icon } from '@iconify/vue';
import { useFocusTrap } from '@vueuse/integrations/useFocusTrap';
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';

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

const handleThemeChange = (isDark: boolean) => {
  // Add any additional handling here if needed
  console.log('Theme changed:', isDark)
}


const handleMenuToggled = () => {
  // Handle language menu toggle
};


const { activate, deactivate } = useFocusTrap(modalContentRef);

// Handle ESC key
const handleKeydown = (e: KeyboardEvent) => {
  if (e.key === 'Escape') {
    closeModal();
  }
};

onMounted(() => {
  activate();
  window.addEventListener('keydown', handleKeydown);
});

onBeforeUnmount(() => {
  deactivate();
  window.removeEventListener('keydown', handleKeydown);
});
</script>
