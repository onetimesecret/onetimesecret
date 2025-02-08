<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useLanguage } from '@/composables/useLanguage';
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
const { currentLocale, supportedLocales, updateLanguage, initializeLanguage } = useLanguage();

const isMenuOpen = ref(false);
const menuItems = ref<HTMLElement[]>([]);

const ariaLabel = computed(() => t('current-language-is-currentlocal', [currentLocale.value]));
const dropdownMode = computed(() => (props.compact ? 'icon' : 'dropdown'));
const dropdownId = `lang-dropdown-${Math.random().toString(36).slice(2, 11)}`;

const toggleMenu = () => {
  isMenuOpen.value = !isMenuOpen.value;
};

const closeMenu = () => {
  isMenuOpen.value = false;
};

const focusNextItem = () => {
  const currentIndex = menuItems.value.indexOf(document.activeElement as HTMLElement);
  const nextIndex = (currentIndex + 1) % menuItems.value.length;
  menuItems.value[nextIndex].focus();
};

const focusPreviousItem = () => {
  const currentIndex = menuItems.value.indexOf(document.activeElement as HTMLElement);
  const previousIndex = (currentIndex - 1 + menuItems.value.length) % menuItems.value.length;
  menuItems.value[previousIndex].focus();
};

const announceLanguageChange = (locale: string) => {
  const liveRegion = document.createElement('div');
  liveRegion.setAttribute('role', 'status');
  liveRegion.setAttribute('aria-live', 'polite');
  liveRegion.setAttribute('aria-atomic', 'true');
  liveRegion.className = 'sr-only';
  liveRegion.textContent = t('language-changed-to-newlocale', [locale]);
  document.body.appendChild(liveRegion);
  setTimeout(() => {
    if (document.body.contains(liveRegion)) {
      document.body.removeChild(liveRegion);
    }
  }, 1000);
};

const changeLocale = async (newLocale: string) => {
  if (newLocale === currentLocale.value) return;

  try {
    await updateLanguage(newLocale);
    emit('localeChanged', newLocale);
    announceLanguageChange(newLocale);
  } catch (err) {
    console.error('Failed to update language:', err);
  } finally {
    closeMenu();
  }
};

const handleClickOutside = (event: MouseEvent) => {
  const target = event.target as HTMLElement;
  if (!target.closest('.relative')) {
    closeMenu();
  }
};

const handleEscapeKey = (event: KeyboardEvent) => {
  if (event.key === 'Escape') {
    closeMenu();
  }
};

onMounted(() => {
  initializeLanguage();
  menuItems.value = Array.from(document.querySelectorAll('[role="menuitem"]')) as HTMLElement[];
  document.addEventListener('click', handleClickOutside);
  document.addEventListener('keydown', handleEscapeKey);
});

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside);
  document.removeEventListener('keydown', handleEscapeKey);
});
</script>

<template>
  <div
    class="relative flex items-center"
    :class="{ 'opacity-60 hover:opacity-100': !isMenuOpen }"
    :aria-haspopup="true"
    :aria-controls="dropdownId"
    :aria-expanded="isMenuOpen">
    <button
      type="button"
      :class="[
        'inline-flex items-center justify-center rounded-md transition-colors',
        'focus:outline-none focus:ring-2 focus:ring-brand-600 dark:focus:ring-brand-400',
        'focus:ring-offset-2 focus:ring-offset-white dark:ring-offset-gray-900',
        dropdownMode === 'icon'
          ? [
              'size-10 p-1',
              'text-gray-900 dark:text-gray-100',
              'hover:bg-gray-200 dark:hover:bg-gray-700',
            ]
          : [
              'w-full px-4 py-2',
              'bg-gray-100 dark:bg-gray-800',
              'text-gray-900 dark:text-gray-100',
              'hover:bg-gray-200 dark:hover:bg-gray-700',
            ],
      ]"
      :aria-label="ariaLabel"
      :aria-expanded="isMenuOpen"
      aria-haspopup="true"
      @click="toggleMenu"
      @keydown.down.prevent="isMenuOpen = true"
      @keydown.enter.prevent="isMenuOpen = true"
      @keydown.space.prevent="isMenuOpen = true">
      <template v-if="compact">
        <OIcon
          class="size-5"
          collection="heroicons"
          name="language" />
      </template>
      <template v-else>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="mr-2 size-5"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          aria-hidden="true">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M3 5h12M9 3v2m1.048 9.5A18.022 18.022 0 016.412 9m6.088 9h7M11 21l5-10 5 10M12.751 5C11.783 10.77 8.07 15.61 3 18.129" />
        </svg>
        {{ currentLocale }}
        <svg
          class="size-5 -mr-1 ml-2"
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 20 20"
          fill="currentColor"
          aria-hidden="true">
          <path
            fill-rule="evenodd"
            d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z"
            clip-rule="evenodd" />
        </svg>
      </template>
    </button>

    <div
      v-if="isMenuOpen"
      class="absolute right-0 bottom-full z-[49] mb-2 w-56 rounded-md bg-white shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none dark:bg-gray-800 dark:ring-white dark:ring-opacity-20"
      role="menu"
      aria-orientation="vertical"
      @keydown.esc="closeMenu"
      @keydown.up.prevent="focusPreviousItem"
      @keydown.down.prevent="focusNextItem">
      <div
        :id="dropdownId"
        class="max-h-60 overflow-y-auto py-1"
        role="none">
        <div
          class="border-b border-gray-200 px-4 py-2 text-sm font-medium text-gray-500 dark:border-gray-700 dark:text-gray-400"
          role="presentation">
          <div class="flex items-center justify-between font-bold text-gray-700 dark:text-gray-100">
            {{ currentLocale }}
            <OIcon
              collection="heroicons"
              name="check-20-solid"
              class="size-5 text-brand-500"
              aria-hidden="true" />
          </div>
        </div>
        <button
          v-for="locale in supportedLocales"
          :key="locale"
          @click="changeLocale(locale)"
          :class="[
            'flex w-full items-center justify-between gap-2 font-brand',
            'px-4 py-2 text-base transition-colors',
            'text-gray-900 dark:text-gray-100',
            'hover:bg-gray-200 dark:hover:bg-gray-700',
            locale === currentLocale
              ? 'bg-gray-100 font-medium text-brand-600 dark:bg-gray-800 dark:text-brand-400'
              : '',
          ]"
          :aria-current="locale === currentLocale ? 'true' : undefined"
          :aria-selected="locale === currentLocale"
          role="menuitem"
          :lang="locale">
          <span>{{ locale }}</span>
        </button>
      </div>
    </div>
  </div>
</template>
