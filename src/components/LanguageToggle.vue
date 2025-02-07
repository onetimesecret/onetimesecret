<!-- src/components/LanguageToggle.vue -->

<script setup lang="ts">
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { WindowService } from '@/services/window.service';
  import { useLanguage } from '@/composables/useLanguage';
  import DropdownToggle from './DropdownToggle.vue';
  import OIcon from './icons/OIcon.vue';

  interface Props {
    compact?: boolean;
  }

  const props = withDefaults(defineProps<Props>(), {
    compact: false,
  });

  const emit = defineEmits<{
    (e: 'localeChanged', locale: string): void;
  }>();

  const { t } = useI18n();
  const { currentLocale, supportedLocales, updateLanguage, saveLanguage, initializeLanguage } =
    useLanguage();
  const dropdownRef = ref<InstanceType<typeof DropdownToggle> | null>(null);
  const cust = WindowService.get('cust');

  const announceLanguageChange = (locale: string) => {
    const liveRegion = document.createElement('div');
    liveRegion.setAttribute('role', 'status');
    liveRegion.setAttribute('aria-live', 'polite');
    liveRegion.className = 'sr-only';
    liveRegion.textContent = t('language-changed-to-newlocale', [locale]);
    document.body.appendChild(liveRegion);
    setTimeout(() => document.body.removeChild(liveRegion), 1000);
  };

  const changeLocale = async (newLocale: string) => {
    try {
      await updateLanguage(newLocale);
      if (cust?.locale) {
        await saveLanguage(newLocale);
      }
      emit('localeChanged', newLocale);
      announceLanguageChange(newLocale);
    } catch (err) {
      console.error('Failed to update language:', err);
    } finally {
      dropdownRef.value?.closeMenu();
    }
  };

  onMounted(() => {
    initializeLanguage();
  });

  const ariaLabel = computed(() => t('current-language-is-currentlocal', [currentLocale]));
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
          'flex items-center justify-between gap-2 font-brand',
          'px-4 py-2 text-base transition-colors duration-200',
          'hover:bg-gray-100 hover:text-gray-900',
          'dark:hover:bg-gray-700 dark:hover:text-gray-100',
          locale === currentLocale
            ? 'bg-gray-100 font-medium text-brandcomdim-600 dark:bg-gray-700 dark:text-brandcomdim-400'
            : 'text-gray-700 dark:text-gray-300',
        ]"
        role="menuitem"
        :aria-current="locale === currentLocale ? 'true' : undefined"
        :lang="locale">
        <span>{{ locale }}</span>
        <OIcon
          v-if="locale === currentLocale"
          collection="heroicons"
          name="check-20-solid"
          class="size-5 text-brand-600 dark:text-brand-400" />
      </a>
    </template>
  </DropdownToggle>
</template>
