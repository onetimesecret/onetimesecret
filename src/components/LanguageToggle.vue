<!-- src/components/LanguageToggle.vue -->

<script setup lang="ts">
  import { WindowService } from '@/services/window.service';
  import { setLanguage } from '@/i18n';
  import { useLanguageStore } from '@/stores/languageStore';
  import { computed, onMounted, ref, nextTick } from 'vue';
  import { useI18n } from 'vue-i18n';

  import DropdownToggle from './DropdownToggle.vue';

  interface Props {
    compact?: boolean;
  }

  const props = withDefaults(defineProps<Props>(), {
    compact: false,
  });

  const { t } = useI18n();
  const emit = defineEmits<{
    (e: 'localeChanged', locale: string): void;
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
      await Promise.all([languageStore.updateLanguage(newLocale), setLanguage(newLocale)]);
      selectedLocale.value = newLocale;
      emit('localeChanged', newLocale);

      // Add an ARIA live announcement
      const liveRegion = document.createElement('div');
      liveRegion.setAttribute('role', 'status');
      liveRegion.setAttribute('aria-live', 'polite');
      liveRegion.className = 'sr-only';  // visually hidden but available to screen readers
      liveRegion.textContent = t('language-changed-to-newlocale', [newLocale]);
      document.body.appendChild(liveRegion);

      // Clean up after announcement
      setTimeout(() => {
        document.body.removeChild(liveRegion);
      }, 1000);

    } catch (err) {
      console.error('Failed to update language:', err);
    } finally {
      dropdownRef.value?.closeMenu();
    }
  };

  onMounted(() => {
    setLanguage(selectedLocale.value);
  });

  const ariaLabel = t('current-language-is-currentlocal', [currentLocale.value]);
  const dropdownMode = computed(() => (props.compact ? 'icon' : 'dropdown'));
</script>

<template>
  <DropdownToggle
    ref="dropdownRef"
    class="text-gray-700 dark:text-gray-300"
    open-direction="up"
    :aria-label="ariaLabel"
    :mode="dropdownMode">
    <template #button-content>
      <template v-if="compact">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="size-5 text-gray-600 dark:text-gray-400"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          aria-hidden="true"
          role="img">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M3 5h12M9 3v2m1.048 9.5A18.022 18.022 0 016.412 9m6.088 9h7M11 21l5-10 5 10M12.751 5C11.783 10.77 8.07 15.61 3 18.129" />
        </svg>
      </template>
      <template v-else>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="mr-2 size-5 text-gray-600 dark:text-gray-400"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M3 5h12M9 3v2m1.048 9.5A18.022 18.022 0 016.412 9m6.088 9h7M11 21l5-10 5 10M12.751 5C11.783 10.77 8.07 15.61 3 18.129" />
        </svg>
        {{ currentLocale }}
      </template>
    </template>

    <template #menu-items>
      <a
        v-for="locale in supportedLocales"
        :key="locale"
        href="#"
        @click.prevent="changeLocale(locale)"
        :class="[
          'block px-4 py-2 text-sm transition-colors duration-200',
          'hover:bg-gray-100 hover:text-gray-900',
          'dark:hover:bg-gray-700 dark:hover:text-gray-100',
          locale === currentLocale
            ? 'bg-gray-100 font-medium text-brandcomdim-600 dark:bg-gray-700 dark:text-brandcomdim-400'
            : 'text-gray-700 dark:text-gray-300',
        ]"
        role="menuitem"
        :aria-current="locale === currentLocale ? 'true' : undefined"
        :lang="locale">
        {{ locale }}
      </a>
    </template>
  </DropdownToggle>
</template>
