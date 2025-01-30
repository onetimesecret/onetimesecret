<!-- src/components/layout/Masthead.vue -->
<script setup lang="ts">
import HeaderUserNav from '@/components/layout/HeaderUserNav.vue';
import SettingsModal from '@/components/modals/SettingsModal.vue';
import { WindowService } from '@/services/window.service';
import type { LayoutProps } from '@/types/ui/layouts';
import OIcon from '@/components/icons/OIcon.vue';
import { computed, ref } from 'vue';
import { useJurisdictionStore } from '@/stores/jurisdictionStore';
import type { Jurisdiction } from '@/schemas/models/jurisdiction';

withDefaults(defineProps<LayoutProps>(), {
  displayMasthead: true,
  displayNavigation: true,
  colonel: false,
});

const windowProps = WindowService.getMultiple([
  'regions_enabled', 'regions', 'authentication', 'authenticated', 'cust',
]);

const colonel = computed(() => windowProps.cust?.role === 'colonel');

// Reactive state
const isSettingsModalOpen = ref(false);

// Methods
const openSettingsModal = () => {
  isSettingsModalOpen.value = true;
};

const closeSettingsModal = () => {
  isSettingsModalOpen.value = false;
};

const jurisdictionStore = useJurisdictionStore();
const currentJurisdiction = computed<Jurisdiction | null>(
  () => jurisdictionStore.getCurrentJurisdiction
);
</script>

<template>

  <div v-if="displayMasthead" class="w-full">
    <div class="flex flex-col items-center justify-between sm:flex-row">
      <div class="mb-4 sm:mb-0">
        <div class="flex flex-col">
          <router-link to="/" class="flex items-center">
            <img id="logo"
                 src="@/assets/img/onetime-logo-v3-xl.svg"
                 class="size-12 rounded-md sm:size-16"
                 height="64"
                 alt="Onetime Secret" />
            <div class="ml-2 flex flex-col">
              <span class="font-brand text-xl font-bold text-gray-800 dark:text-white">
                Onetime Secret
              </span>
              <div v-if="currentJurisdiction"
                   class="mt-0.5 w-fit rounded-full
                          bg-gray-100 px-1.5 py-0.5 text-xs font-medium
                          text-gray-600 dark:bg-gray-800 dark:text-gray-400">
                {{ currentJurisdiction.identifier }}
              </div>
            </div>
          </router-link>
        </div>
      </div>
    <nav v-if="displayNavigation"
         role="navigation"
         aria-label="Main navigation"
         class="flex flex-wrap items-center justify-center gap-4 font-brand text-sm sm:justify-end sm:text-base">
      <template v-if="windowProps.authenticated && windowProps.cust">
        <HeaderUserNav :cust="windowProps.cust"
                       :colonel="colonel" />

        <button @click="openSettingsModal"
                class="text-xl text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white"
                aria-label="Settings">
          <OIcon class="size-5"
                collection="material-symbols"
                name="settings" />
        </button>

        <SettingsModal :is-open="isSettingsModalOpen"
                       @close="closeSettingsModal" />

        <span class="text-gray-400"
              aria-hidden="true"
              role="separator">|</span>

        <router-link to="/logout"
                     class="text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white"
                     :title="$t('web.COMMON.header_logout')"
                     :aria-label="$t('web.COMMON.header_logout')">
          <OIcon class="size-5"
                collection="heroicons"
                name="arrow-right-on-rectangle-solid" />
        </router-link>
      </template>

      <template v-else>
        <template v-if="windowProps.authentication.enabled">
          <router-link v-if="windowProps.authentication.signup"
                       to="/signup"
                       title="Signup - Individual and Business plans"
                       class="font-bold text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
            {{ $t('web.COMMON.header_create_account') }}
          </router-link>
          <span class="text-gray-400"
                aria-hidden="true"
                role="separator">|</span>
          <router-link to="/about"
                       title="About Onetime Secret"
                       class="text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
            {{ $t('web.COMMON.header_about') }}
          </router-link>
          <span class="text-gray-400"
                aria-hidden="true"
                role="separator">|</span>
          <router-link v-if="windowProps.authentication.signin"
                       to="/signin"
                       title="Log in to Onetime Secret"
                       class="text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
            {{ $t('web.COMMON.header_sign_in') }}
          </router-link>
        </template>

        <router-link v-else
                     to="/about"
                     title="About Onetime Secret"
                     class="text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
          {{ $t('web.COMMON.header_about') }}
        </router-link>
      </template>
    </nav>
  </div>
</div>
</template>
