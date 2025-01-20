<!-- src/components/LanguageToggle.vue -->
<script setup lang="ts">
import { WindowService } from '@/services/window.service';
import { setLanguage } from '@/i18n';
import { useLanguageStore } from '@/stores/languageStore';
import { computed, onMounted, ref, nextTick } from 'vue';

import DropdownToggle from './DropdownToggle.vue';

const emit = defineEmits<{
  (e: 'localeChanged', locale: string): void
}>();

const languageStore = useLanguageStore();
const supportedLocales = languageStore.getSupportedLocales;

const cust = WindowService.get('cust');

const selectedLocale = ref(languageStore.determineLocale(cust?.locale ?? 'en'));

const currentLocale = computed(() => selectedLocale.value);

const dropdownRef = ref<InstanceType<typeof DropdownToggle> | null>(null);

const changeLocale = async (newLocale: string) => {
  await nextTick(); // Ensure store is ready

  if (!languageStore._initialized) {
    console.debug('Language store not initialized yet');
  }

  if (!languageStore.getSupportedLocales?.includes(newLocale)) {
    console.warn(`Unsupported locale: ${newLocale}`);
    return;
  }

  try {
    if (cust?.locale) {
      cust.locale = newLocale;
    }
    await Promise.all([
      languageStore.updateLanguage(newLocale),
      setLanguage(newLocale)
    ]);
    selectedLocale.value = newLocale;
    emit('localeChanged', newLocale);
  } catch (err) {
    console.error('Failed to update language:', err);
  } finally {
    dropdownRef.value?.closeMenu();
  }
};

onMounted(() => {
  setLanguage(selectedLocale.value);
});
</script>

<template>
  <DropdownToggle
    ref="dropdownRef"
    ariaLabel="Change language"
    open-direction="down">
    <template #button-content>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="mr-2 size-5"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M3 5h12M9 3v2m1.048 9.5A18.022 18.022 0 016.412 9m6.088 9h7M11 21l5-10 5 10M12.751 5C11.783 10.77 8.07 15.61 3 18.129"
        />
      </svg>
      {{ currentLocale }}
    </template>
    <template #menu-items>
      <a
        v-for="locale in supportedLocales"
        :key="locale"
        href="#"
        @click.prevent="changeLocale(locale)"
        :class="[
          'block px-4 py-2 text-sm hover:bg-gray-100 hover:text-gray-900 dark:hover:bg-gray-700 dark:hover:text-gray-100',
          locale === currentLocale ? 'bg-gray-100 font-bold text-indigo-600 dark:bg-gray-700 dark:text-indigo-400' : 'text-gray-700 dark:text-gray-300'
        ]"
        role="menuitem">
        {{ locale }}
      </a>
    </template>
  </DropdownToggle>
</template>
