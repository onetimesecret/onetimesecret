<script setup lang="ts">
import { ref } from 'vue';

interface Props {
  enabled?: boolean;
  withRecipient?: boolean;
  withPassphrase?: boolean;
  withExpiry?: boolean;
}

const props = withDefaults(defineProps<Props>(), {
  enabled: true,
  withRecipient: false,
  withPassphrase: true,
  withExpiry: true,
})

const showPassphrase = ref(false);
const currentPassphrase = ref('');
const selectedLifetime = ref('604800.0');

const lifetimeOptions = [
  { value: '1209600.0', label: '14 days' },
  { value: '604800.0', label: '7 days' },
  { value: '259200.0', label: '3 days' },
  { value: '86400.0', label: '1 day' },
  { value: '43200.0', label: '12 hours' },
  { value: '14400.0', label: '4 hours' },
  { value: '3600.0', label: '1 hour' },
  { value: '1800.0', label: '30 minutes' },
  { value: '300.0', label: '5 minutes' },
];

//const getSelectedLifetimeLabel = computed(() => {
//  const option = lifetimeOptions.find(opt => opt.value === selectedLifetime.value);
//  return option ? option.label : 'Not selected';
//});

const togglePassphrase = () => {
  showPassphrase.value = !showPassphrase.value;
};
</script>

<template>
  <div class="bg-white dark:bg-gray-800 shadow-lg rounded-lg p-3 mb-3">
    <h3 class="text-lg font-medium text-gray-500 dark:text-gray-400 mb-2">Privacy Options</h3>
    <div class="space-y-6">
      <div class="flex flex-col md:flex-row md:space-x-4 space-y-6 md:space-y-0">
        <!-- Passphrase Field -->
        <div class="flex-1">
          <label for="currentPassphrase"
                 class="sr-only block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Passphrase:
          </label>
          <div class="relative">
            <input :type="showPassphrase ? 'text' : 'password'"
                   id="currentPassphrase"
                   v-model="currentPassphrase"
                   autocomplete="unique-passphrase"
                   placeholder="Enter a passphrase"
                   class="w-full px-4 py-2 border border-gray-300 rounded-md focus:ring-brandcomp-500 focus:border-brandcomp-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white">
            <button type="button"
                    @click="togglePassphrase()"
                    class="absolute inset-y-0 right-0 flex items-center px-3 text-gray-500 dark:text-gray-300">
              <svg v-if="showPassphrase"
                   xmlns="http://www.w3.org/2000/svg"
                   class="h-5 w-5"
                   viewBox="0 0 20 20"
                   fill="currentColor">
                <path d="M10 12a2 2 0 100-4 2 2 0 000 4z" />
                <path fill-rule="evenodd"
                      d="M.458 10C1.732 5.943 5.522 3 10 3s8.268 2.943 9.542 7c-1.274 4.057-5.064 7-9.542 7S1.732 14.057.458 10zM14 10a4 4 0 11-8 0 4 4 0 018 0z"
                      clip-rule="evenodd" />
              </svg>
              <svg v-else
                   xmlns="http://www.w3.org/2000/svg"
                   class="h-5 w-5"
                   viewBox="0 0 20 20"
                   fill="currentColor">
                <path fill-rule="evenodd"
                      d="M3.707 2.293a1 1 0 00-1.414 1.414l14 14a1 1 0 001.414-1.414l-1.473-1.473A10.014 10.014 0 0019.542 10C18.268 5.943 14.478 3 10 3a9.958 9.958 0 00-4.512 1.074l-1.78-1.781zm4.261 4.26l1.514 1.515a2.003 2.003 0 012.45 2.45l1.514 1.514a4 4 0 00-5.478-5.478z"
                      clip-rule="evenodd" />
                <path
                      d="M12.454 16.697L9.75 13.992a4 4 0 01-3.742-3.741L2.335 6.578A9.98 9.98 0 00.458 10c1.274 4.057 5.065 7 9.542 7 .847 0 1.669-.105 2.454-.303z" />
              </svg>
            </button>
          </div>
        </div>

        <!-- Lifetime Field -->
        <div class="flex-1">
          <label for="lifetime"
                 class="sr-only block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Lifetime:
          </label>
          <select id="lifetime"
                  name="ttl"
                  v-model="selectedLifetime"
                  class="w-full px-4 py-2 border border-gray-300 rounded-md focus:ring-brandcomp-500 focus:border-brandcomp-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white">
            <option value="" disabled>Select duration</option>
            <option v-for="option in lifetimeOptions" :key="option.value" :value="option.value">
            <span class="text-gray-500">Expires in</span> {{ option.label }}
            </option>
          </select>
        </div>
      </div>

      <!-- Recipient Field (if needed) -->
      <div v-if="props.withRecipient"
           class="flex flex-col">
        <label for="recipient"
               class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
          Recipient Address:
        </label>
        <input type="email"
               id="recipient"
               name="recipient[]"
               placeholder="example@onetimesecret.com"
               class="w-full px-4 py-2 border border-gray-300 rounded-md focus:ring-brandcomp-500 focus:border-brandcomp-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white">
      </div>
    </div>
  </div>
</template>
