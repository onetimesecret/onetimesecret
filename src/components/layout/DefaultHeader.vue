<script setup lang="ts">
import HeaderUserNav from '@/components/layout/HeaderUserNav.vue';
import SettingsModal from '@/components/modals/SettingsModal.vue';
import type { LayoutProps } from '@/types/ui/layouts';
import { Icon } from '@iconify/vue';
import { computed, ref } from 'vue';

const props = withDefaults(defineProps<LayoutProps>(), {
  displayMasthead: true,
  displayNavigation: true,
  colonel: false,
});

const colonel = computed(() => props.cust?.role === 'colonel');

// Reactive state
const isSettingsModalOpen = ref(false);

// Methods
const openSettingsModal = () => {
  isSettingsModalOpen.value = true;
};

const closeSettingsModal = () => {
  isSettingsModalOpen.value = false;
};

</script>

<template>
  <header class="bg-white dark:bg-gray-900">
    <div class="container mx-auto min-w-[320px] max-w-2xl p-4">
      <div
        v-if="displayMasthead"
        class="w-full">
        <div class="flex flex-col items-center justify-between sm:flex-row">
          <div class="mb-4 sm:mb-0">
            <router-link
              to="/"
              class="flex items-center">
              <img
                id="logo"
                src="@/assets/img/onetime-logo-v3-xl.svg"
                class="size-12 rounded-md sm:size-16"
                alt="Onetime Secret"
              />
              <span class="ml-2 font-brand text-xl font-bold text-gray-800 dark:text-white">
                Onetime Secret
              </span>
            </router-link>
          </div>

          <nav
            v-if="displayNavigation"
            role="navigation"
            aria-label="Main navigation"
            class="flex flex-wrap items-center justify-center gap-4 font-brand text-sm sm:justify-end sm:text-base">
            <template v-if="authenticated && cust">
              <HeaderUserNav
                :cust="cust"
                :colonel="colonel"
              />

              <button
                @click="openSettingsModal"
                class="text-xl text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white"
                aria-label="Settings">
                <Icon
                  icon="material-symbols:settings"
                  aria-hidden="true"
                />
              </button>

              <SettingsModal
                :is-open="isSettingsModalOpen"
                @close="closeSettingsModal"
              />

              <span
                class="text-gray-400"
                aria-hidden="true"
                role="separator">|</span>

              <router-link
                to="/logout"
                class="text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white"
                :title="$t('web.COMMON.header_logout')"
                :aria-label="$t('web.COMMON.header_logout')">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="size-6"
                  aria-hidden="true">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M15.75 9V5.25A2.25 2.25 0 0013.5 3h-6a2.25 2.25 0 00-2.25 2.25v13.5A2.25 2.25 0 007.5 21h6a2.25 2.25 0 002.25-2.25V15m3 0l3-3m0 0l-3-3m3 3H9"
                  />
                </svg>
              </router-link>
            </template>

            <template v-else>
              <template v-if="authentication.enabled">
                <router-link
                  v-if="authentication.signup"
                  to="/signup"
                  title="Signup - Individual and Business plans"
                  class="font-bold text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
                  {{ $t('web.COMMON.header_create_account') }}
                </router-link>
                <span
                  class="text-gray-400"
                  aria-hidden="true"
                  role="separator">|</span>
                <router-link
                  to="/about"
                  title="About Onetime Secret"
                  class="text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
                  {{ $t('web.COMMON.header_about') }}
                </router-link>
                <span
                  class="text-gray-400"
                  aria-hidden="true"
                  role="separator">|</span>
                <router-link
                  v-if="authentication.signin"
                  to="/signin"
                  title="Log in to Onetime Secret"
                  class="text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
                  {{ $t('web.COMMON.header_sign_in') }}
                </router-link>
              </template>

              <router-link
                v-else
                to="/about"
                title="About Onetime Secret"
                class="text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
                {{ $t('web.COMMON.header_about') }}
              </router-link>
            </template>
          </nav>
        </div>
      </div>
    </div>
  </header>
</template>

<style>
.focus-visible:focus {
  @apply outline-none ring-2 ring-brand-500 ring-offset-2 dark:ring-offset-gray-800;
}
</style>
