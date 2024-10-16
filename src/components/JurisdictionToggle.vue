<!-- src/components/JurisdictionToggle.vue -->
<template>
  <DropdownToggle ref="dropdownRef"
                  ariaLabel="Change jurisdiction">
    <template #button-content>
      <svg xmlns="http://www.w3.org/2000/svg"
           class="h-5 w-5 mr-2"
           fill="none"
           viewBox="0 0 24 24"
           stroke="currentColor">
        <!-- Material Design Icons mdi:database -->
        <path stroke-width="0.5"
              fill="currentColor"
              d="M12 19c-3.87 0-6-1.5-6-2v-2.23c1.61.78 3.72 1.23 6 1.23c.35 0 .69-.03 1.03-.05c-.03-.15-.03-.3-.03-.45c0-.54.09-1.06.24-1.56c-.41.06-.82.06-1.24.06c-2.42 0-4.7-.6-6-1.55V9.64c1.47.83 3.61 1.36 6 1.36s4.53-.53 6-1.36v.39c.17-.03.33-.03.5-.03c.5 0 1 .08 1.5.22V7c0-2.21-3.58-4-8-4S4 4.79 4 7v10c0 2.21 3.59 4 8 4c1.06 0 2.07-.11 3-.29c-.38-.57-.75-1.21-1.07-1.86c-.59.09-1.22.15-1.93.15m0-14c3.87 0 6 1.5 6 2s-2.13 2-6 2s-6-1.5-6-2s2.13-2 6-2m6.5 7c-1.9 0-3.5 1.6-3.5 3.5c0 2.6 3.5 6.5 3.5 6.5s3.5-3.9 3.5-6.5c0-1.9-1.6-3.5-3.5-3.5m0 4.8c-.7 0-1.2-.6-1.2-1.2c0-.7.6-1.2 1.2-1.2s1.2.6 1.2 1.2c.1.6-.5 1.2-1.2 1.2" />
      </svg>
      {{ currentJurisdiction }}
    </template>
    <template #menu-items>
      <a v-for="jurisdiction in supportedJurisdictions"
         :key="jurisdiction"
         href="#"
         @click.prevent="changeJurisdiction(jurisdiction)"
         :class="[
          'block px-4 py-2 text-sm hover:bg-gray-100 dark:hover:bg-gray-700 hover:text-gray-900 dark:hover:text-gray-100',
          jurisdiction === currentJurisdiction ? 'text-indigo-600 dark:text-indigo-400 font-bold bg-gray-100 dark:bg-gray-700' : 'text-gray-700 dark:text-gray-300'
        ]"
         role="menuitem">
        {{ jurisdiction }}
      </a>
    </template>
  </DropdownToggle>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import { useJurisdictionStore } from '@/stores/jurisdictionStore';
import DropdownToggle from './DropdownToggle.vue';

const emit = defineEmits(['jurisdictionChanged', 'updateCustomer']);

const jurisdictionStore = useJurisdictionStore();
const supportedJurisdictions = jurisdictionStore.getSupportedJurisdictions;

const selectedJurisdiction = ref(jurisdictionStore.determineJurisdiction());

const currentJurisdiction = computed(() => selectedJurisdiction.value);

const dropdownRef = ref<InstanceType<typeof DropdownToggle> | null>(null);

const changeJurisdiction = async (newJurisdiction: string) => {
  if (jurisdictionStore.getSupportedJurisdictions.includes(newJurisdiction)) {
    try {
      await jurisdictionStore.updateJurisdiction(newJurisdiction);
      selectedJurisdiction.value = newJurisdiction;
      emit('jurisdictionChanged', newJurisdiction);

      // Instead of directly modifying cust.value, emit an event or call a method
      // to update the customer object in the parent component or global state
      emit('updateCustomer', { jurisdiction: newJurisdiction });
    } catch (err) {
      console.error('Failed to update jurisdiction:', err);
    } finally {
      dropdownRef.value?.closeMenu();
    }
  }
};

onMounted(() => {
  // Any initialization logic for jurisdiction, if needed
});
</script>
