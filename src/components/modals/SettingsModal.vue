<template>
  <div v-if="isOpen"
       class="fixed inset-0 z-50 overflow-y-auto bg-black/50 backdrop-blur-xs flex items-center justify-center"
       aria-labelledby="settings-modal"
       role="dialog"
       aria-modal="true">
    <div class="relative w-full max-w-lg mx-auto bg-white dark:bg-gray-800 rounded-xl shadow-2xl overflow-hidden transition-all duration-300 ease-out transform"
         @click.stop>
      <div class="flex flex-col h-[80vh]"> <!-- Set a fixed height here -->
        <!-- Header -->
        <div class="flex-shrink-0 flex justify-between items-center p-4 border-b border-gray-200 dark:border-gray-700">
          <h2 id="settings-modal"
              class="text-2xl font-bold text-gray-900 dark:text-white">Settings</h2>
          <button @click="closeModal"
                  class="text-gray-400 hover:text-gray-500 dark:text-gray-300 dark:hover:text-gray-200 transition-colors duration-200"
                  aria-label="Close settings">
            <svg class="h-6 w-6"
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
        <div class="flex-shrink-0 flex border-b border-gray-200 dark:border-gray-700">
          <button v-for="tab in tabs"
                  :key="tab"
                  @click="activeTab = tab"
                  class="px-4 py-2 font-medium text-base transition-colors duration-200"
                  :class="[activeTab === tab ? 'text-brand-600 border-b-2 border-brand-600' : 'text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200']">
            {{ tab }}
          </button>
        </div>

        <!-- Content -->
        <div class="flex-grow overflow-y-auto p-4">
          <!-- General Tab -->
          <div v-if="activeTab === 'General'">
            <div class="space-y-4">
              <h3 class="text-lg font-semibold text-gray-900 dark:text-white">Appearance</h3>
              <div class="flex items-center justify-between">
                <span class="text-gray-700 dark:text-gray-300">Theme</span>
                <ThemeToggle />
              </div>
            </div>

            <div class="space-y-4 mt-6">
              <h3 class="text-lg font-semibold text-gray-900 dark:text-white">Language</h3>
              <LanguageToggle @menuToggled="handleMenuToggled" />
            </div>

            <div class="space-y-4 mt-6">
              <h3 class="text-lg font-semibold text-gray-900 dark:text-white">Jurisdiction</h3>
              <div class="bg-gray-100 dark:bg-gray-700 p-3 rounded-md">
                <p class="text-sm text-gray-600 dark:text-gray-300">Your current jurisdiction is <span
                        class="font-semibold">UK</span>. This is determined by the domain you're accessing.</p>
                <p class="text-sm text-gray-600 dark:text-gray-300 mt-2">To learn more about accounts in other regions,
                  please <a href="#"
                     class="text-brand-600 hover:underline">contact support</a>.</p>
              </div>
            </div>
          </div>

          <!-- Notifications Tab -->
          <div v-if="activeTab === 'Notifications'">
            <div class="space-y-4">
              <h3 class="text-lg font-semibold text-gray-900 dark:text-white">Email Notifications</h3>
              <div class="flex items-center justify-between">
                <span class="text-gray-700 dark:text-gray-300">Read receipts</span><Icon icon="info" />
                <label class="relative inline-flex items-center cursor-pointer">
                  <input type="checkbox"
                         value=""
                         class="sr-only peer">
                  <div
                       class="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-brand-300 dark:peer-focus:ring-brand-800 rounded-full peer dark:bg-gray-700 peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all dark:border-gray-600 peer-checked:bg-brand-600">
                  </div>
                </label>
              </div>
            </div>

            <div class="space-y-4 mt-6">
              <h3 class="text-lg font-semibold text-gray-900 dark:text-white">Secret Expiry Reminders</h3>
              <div class="flex items-center justify-between">
                <span class="text-gray-700 dark:text-gray-300">Send reminders before secret expiry</span>
                <label class="relative inline-flex items-center cursor-pointer">
                  <input type="checkbox"
                         value=""
                         class="sr-only peer">
                  <div
                       class="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-brand-300 dark:peer-focus:ring-brand-800 rounded-full peer dark:bg-gray-700 peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all dark:border-gray-600 peer-checked:bg-brand-600">
                  </div>
                </label>
              </div>
            </div>
          </div>

          <!-- Security Tab -->
          <div v-if="activeTab === 'Security'">
            <div class="space-y-4">
              <h3 class="text-lg font-semibold text-gray-900 dark:text-white">Two-Factor Authentication</h3>
              <button
                      class="px-4 py-2 bg-brand-600 text-white rounded-md hover:bg-brand-700 transition-colors duration-200">Enable
                2FA</button>
            </div>

            <div class="space-y-4 mt-6">
              <h3 class="text-lg font-semibold text-gray-900 dark:text-white">Password</h3>
              <button
                      class="px-4 py-2 bg-gray-200 text-gray-800 dark:bg-gray-600 dark:text-white rounded-md hover:bg-gray-300 dark:hover:bg-gray-500 transition-colors duration-200">Change
                Password</button>
            </div>
          </div>
        </div>

        <!-- Footer -->
        <div class="flex-shrink-0 p-4 bg-gray-50 dark:bg-gray-700 flex justify-end">
          <button @click="closeModal"
                  class="px-4 py-2 bg-slate-500 text-white rounded-md hover:bg-slate-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-slate-500 transition-colors duration-200">
            Done & Close
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import LanguageToggle from '@/components/LanguageToggle.vue';
import { Icon } from '@iconify/vue';

defineProps<{
  isOpen: boolean;
}>();

const emit = defineEmits<{
  (e: 'close'): void;
}>();

const tabs = ['General', 'Notifications', 'Security'];
const activeTab = ref('General');

const closeModal = () => {
  emit('close');
};

const handleMenuToggled = () => {
  // Handle language menu toggle
};
</script>
