
<template>
  <SecretFormDrawer title="Privacy Options">
    <div class="space-y-6 mt-4">
      <div class="flex flex-col md:flex-row md:space-x-4 space-y-6 md:space-y-0">
        <!-- Passphrase Field -->
        <div v-if="props.withPassphrase"
             class="flex-1">
          <label for="currentPassphrase"
                 class="sr-only">Passphrase:</label>
          <div class="relative">
            <input :type="showPassphrase ? 'text' : 'password'"
                   tabindex="3"
                   id="currentPassphrase"
                   v-model="currentPassphrase"
                   name="passphrase"
                   autocomplete="unique-passphrase"
                   placeholder="Enter a passphrase"
                   aria-label="Passphrase"
                   class="w-full px-4 py-2 border rounded-md
                   border-gray-300 focus:ring-brandcomp-500 focus:border-brandcomp-500
                   dark:bg-gray-700 dark:border-gray-600 dark:text-white
                   transition-colors duration-200">
            <button type="button"
                    @click="togglePassphrase()"
                    class="absolute inset-y-0 right-0 flex items-center px-3 text-gray-500 dark:text-gray-300
                           transition-colors duration-200">
              <Icon :icon="showPassphrase ? 'mdi:eye' : 'mdi:eye-off'"
                    class="w-5 h-5" />
            </button>
          </div>
        </div>

        <!-- Lifetime Field -->
        <div v-if="props.withExpiry"
             class="flex-1">
          <label for="lifetime"
                 class="sr-only">Lifetime:</label>
          <select id="lifetime"
                  tabindex="4"
                  name="ttl"
                  v-model="selectedLifetime"
                  class="w-full px-4 py-2 border rounded-md
                  border-gray-300 focus:ring-brandcomp-500 focus:border-brandcomp-500
                  dark:bg-gray-700 dark:border-gray-600 dark:text-white
                  transition-colors duration-200">
            <option value=""
                    disabled>Select duration</option>
            <option v-for="option in filteredLifetimeOptions"
                    :key="option.value"
                    :value="option.value">
              Expires in {{ option.label }}
            </option>
          </select>
        </div>
      </div>

      <!-- Recipient Field (if needed) -->
      <div v-if="props.withRecipient"
           class="flex flex-col">
        <label for="recipient"
               class="block font-brand text-sm font-medium text-gray-500 dark:text-gray-300 mb-2
                      transition-colors duration-200">
          Recipient Address
        </label>
        <input type="email"
               tabindex="5"
               id="recipient"
               name="recipient[]"
               placeholder="tom@myspace.com"
               class="w-full px-4 py-2 border border-gray-300 rounded-md focus:ring-brandcomp-500 focus:border-brandcomp-500
                      dark:bg-gray-700 dark:border-gray-600 dark:text-white
                      transition-colors duration-200">
      </div>
    </div>
  </SecretFormDrawer>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue';
import { Icon } from '@iconify/vue';
import { useWindowProp } from '@/composables/useWindowProps';
import SecretFormDrawer from './SecretFormDrawer.vue';

const plan = useWindowProp('plan');

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

const filteredLifetimeOptions = computed(() => {
  const planTtl = plan.value?.options?.ttl || 0;
  return lifetimeOptions.filter(option => parseFloat(option.value) <= planTtl);
});

const togglePassphrase = () => {
  showPassphrase.value = !showPassphrase.value;
};

</script>
