<template>
  <button
    type="button"
    class="inline-flex items-center justify-center w-full rounded-md border border-gray-300 shadow-sm px-4 py-2 bg-white text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-gray-100 focus:ring-indigo-500"
    :aria-expanded="isMenuOpen"
    aria-haspopup="true"
    @click="toggleMenu"
    @keydown.down.prevent="openMenu"
    @keydown.enter.prevent="openMenu"
    @keydown.space.prevent="openMenu">
    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 5h12M9 3v2m1.048 9.5A18.022 18.022 0 016.412 9m6.088 9h7M11 21l5-10 5 10M12.751 5C11.783 10.77 8.07 15.61 3 18.129" />
    </svg>
    {{ currentLocale }}
    <svg class="ml-2 -mr-1 h-5 w-5" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
      <path fill-rule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clip-rule="evenodd" />
    </svg>
  </button>

  <div
    v-if="isMenuOpen"
    class="origin-bottom-right absolute right-0 bottom-full mb-2 w-56 rounded-md shadow-lg bg-white ring-1 ring-black ring-opacity-5 focus:outline-none"
    role="menu"
    aria-orientation="vertical"
    @keydown.esc="closeMenu"
    @keydown.up.prevent="focusPreviousItem"
    @keydown.down.prevent="focusNextItem">
    <div class="py-1 max-h-60 overflow-y-auto" role="none">
      <a
        v-for="locale in supportedLocales"
        :key="locale"
        href="#"
        @click.prevent="changeLocale(locale)"
        :class="[
          'block px-4 py-2 text-base hover:bg-gray-100 hover:text-gray-900',
          locale === currentLocale ? 'text-brandcomp-700 font-bold bg-gray-200' : 'text-gray-700'
        ]"
        role="menuitem">
        {{ locale }}
      </a>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, computed } from 'vue';
import { setLanguage } from '@/i18n';
import { useLanguageStore } from '@/stores/languageStore';
import { useWindowProp } from '@/composables/useWindowProps.js';

const emit = defineEmits(['localeChanged']);

const languageStore = useLanguageStore();
const supportedLocales = languageStore.getSupportedLocales;

// Use window.locale if available, otherwise fallback to store value
//const windowLocale = useUnrefWindowProp('locale');
const cust = useWindowProp('cust');

const currentLocale = computed(() => {
  const storeLocale = languageStore.getCurrentLocale;
  const custLocale = cust?.value?.locale;

  // First, try to use the customer-specific locale if it's supported
  if (custLocale && supportedLocales.includes(custLocale)) {
    return custLocale;
  }

  // If not, fall back to the store's current locale
  return storeLocale || languageStore.defaultLocale;
});

const isMenuOpen = ref(false);
const menuItems = ref<HTMLElement[]>([]);

const toggleMenu = () => {
  isMenuOpen.value = !isMenuOpen.value;
};

const openMenu = () => {
  isMenuOpen.value = true;
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


const changeLocale = async (newLocale: string) => {
  if (languageStore.getSupportedLocales.includes(newLocale)) {
    try {
      await languageStore.updateLanguage(newLocale);
      await setLanguage(newLocale);
      emit('localeChanged', newLocale);
    } catch (err) {
      console.error('Failed to update language:', err);
    } finally {
      closeMenu();
    }
  }
};


onMounted(async () => {
  menuItems.value = Array.from(document.querySelectorAll('[role="menuitem"]')) as HTMLElement[];

  // Ensure that the i18n system is updated
  //await setLanguage(currentLocale.value);
});

/**
DON'T DELETE

//      try {
//        const response = await axios.post('/api/v2/account/update-locale', {
//          locale: newLocale,
//          shrimp: csrfStore.shrimp
//        });
//
//        // Update the CSRF shrimp if it's returned in the response
//        if (response.data && response.data.shrimp) {
//          csrfStore.updateShrimp(response.data.shrimp);
//        }
//
//        return true;
//      } catch (error) {
//        // Set error, but don't revert the local change
//        this.error = 'Failed to update language on server';
//
//        // Check if the error is due to an invalid CSRF token
//        if (axios.isAxiosError(error) && error.response?.status === 403) {
//          console.log('CSRF token might be invalid. Checking validity...');
//          await csrfStore.checkShrimpValidity();
//
//          if (!csrfStore.isValid) {
//            console.log('CSRF token is invalid. Please refresh the page or try again.');
//          }
//        }
//
//        return false;
//      } finally {
//        this.isLoading = false;
//      }
*/
</script>
