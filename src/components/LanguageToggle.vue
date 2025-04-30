<script setup lang="ts">
  import { computed, onMounted, onUnmounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useLanguage } from '@/composables/useLanguage';

  import OIcon from './icons/OIcon.vue';

  interface Props {
    compact?: boolean;
    /**
     * Tailwind class to control the maximum height of the dropdown menu.
     * Defaults to 'max-h-72'.
     */
    maxHeight?: string;
  }

  const props = withDefaults(defineProps<Props>(), {
    compact: false,
    maxHeight: 'max-h-72', // Default max height class
  });

  const emit = defineEmits<{
    (e: 'localeChanged', locale: string): void;
  }>();

  const { t } = useI18n();
  const { currentLocale, supportedLocalesWithNames, updateLanguage, initializeLanguage } = useLanguage();

  const isMenuOpen = ref(false);
  const menuItems = ref<HTMLElement[]>([]);

  const ariaLabel = computed(() => t('current-language-is-currentlocal', [currentLocaleName.value]));
  const dropdownMode = computed(() => (props.compact ? 'icon' : 'dropdown'));
  const dropdownId = `lang-dropdown-${Math.random().toString(36).slice(2, 11)}`;

  const currentLocaleName = computed(() => {
    // Safely access the locale name, fallback to the locale code
    return supportedLocalesWithNames?.[currentLocale.value] || currentLocale.value;
  });

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
    // Safely access the locale name for announcement
    const localeName = supportedLocalesWithNames?.[locale] || locale;
    liveRegion.textContent = t('language-changed-to-newlocale', [localeName]);
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
    // Note: Querying menu items here might be too early if the menu isn't rendered initially.
    // Consider updating menuItems when the menu opens if issues persist.
    menuItems.value = Array.from(document.querySelectorAll(`[id='${dropdownId}'] [role="menuitem"]`)) as HTMLElement[];
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
    :aria-haspopup="true"
    :aria-controls="dropdownId"
    :aria-expanded="isMenuOpen">
    <!-- Button remains the same -->
    <button
      type="button"
      :class="[
        'inline-flex items-center justify-center rounded-md transition-colors',
        'focus:outline-none focus:ring-2 focus:ring-brand-600 dark:focus:ring-brand-400',
        'focus:ring-offset-2 focus:ring-offset-white dark:ring-offset-gray-900',
        'text-gray-700 dark:text-gray-400',
        'hover:bg-gray-200 hover:text-gray-900 dark:hover:bg-gray-700 dark:hover:text-gray-200',
        dropdownMode === 'icon'
          ? ['size-10 p-1']
          : ['w-full px-4 py-2', 'bg-gray-100 dark:bg-gray-800'],
      ]"
      :aria-label="ariaLabel"
      :aria-expanded="isMenuOpen"
      aria-haspopup="true"
      @click="toggleMenu"
      @keydown.down.prevent="isMenuOpen = true"
      @keydown.enter.prevent="isMenuOpen = true"
      @keydown.space.prevent="isMenuOpen = true">
      <!-- Button content remains the same -->
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
        {{ currentLocaleName }}
        <svg
          class="-mr-1 ml-2 size-5"
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
      :class="[
        'absolute bottom-full right-0 z-[49] mb-2 w-56 rounded-md',
        'bg-white shadow-lg ring-1 ring-black/5 focus:outline-none',
        'dark:bg-gray-800 dark:ring-white/20',
      ]"
      role="menu"
      aria-orientation="vertical"
      @keydown.esc="closeMenu"
      @keydown.up.prevent="focusPreviousItem"
      @keydown.down.prevent="focusNextItem">
      <!-- Apply the maxHeight prop here -->
      <div
        :id="dropdownId"
        :class="['overflow-y-auto py-1', props.maxHeight]"
        role="none">
        <!-- prettier-ignore-attribute class -->
        <div
          class="border-b border-gray-200 px-4 py-2 text-sm font-medium
               text-gray-500 dark:border-gray-700 dark:text-gray-400"
          role="presentation">
          <div class="flex items-center justify-between font-bold text-gray-700 dark:text-gray-100">
            {{ currentLocaleName }}
            <OIcon
              collection="heroicons"
              name="check-20-solid"
              class="size-5 text-brand-500"
              aria-hidden="true" />
          </div>
        </div>
        <!-- Menu items remain the same -->
        <button
          v-for="(name, locale) in supportedLocalesWithNames"
          :key="locale"
          @click="changeLocale(locale)"
          :class="[
            'flex w-full items-center justify-between gap-2 font-brand',
            'px-4 py-2 text-left text-base transition-colors',
            'text-gray-900 dark:text-gray-100',
            'hover:bg-gray-200 dark:hover:bg-gray-700',
            'focus:bg-gray-200 focus:outline-none dark:focus:bg-gray-700',
            locale === currentLocale
              ? 'bg-gray-100 font-medium text-brand-600 dark:bg-gray-800 dark:text-brand-400'
              : 'font-normal',
          ]"
          :aria-current="locale === currentLocale ? 'true' : undefined"
          :aria-selected="locale === currentLocale"
          role="menuitem"
          :lang="locale">
          <span class="flex min-w-0 flex-1 items-baseline">
            <span
              class="truncate"
              :title="name">{{ name }}</span>
            <span class="ml-2 shrink-0 text-sm text-gray-500 dark:text-gray-400">
              {{ locale }}
            </span>
          </span>
          <OIcon
            v-if="locale === currentLocale"
            collection="heroicons"
            name="check-20-solid"
            class="ml-2 size-5 shrink-0 text-brand-500 dark:text-brand-400"
            aria-hidden="true" />
        </button>
      </div>
    </div>
  </div>
</template>
