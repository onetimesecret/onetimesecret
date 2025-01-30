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
import { Menu, MenuButton, MenuItems, MenuItem } from '@headlessui/vue'

  withDefaults(defineProps<LayoutProps>(), {
    displayMasthead: true,
    displayNavigation: true,
    colonel: false,
  });

  const windowProps = WindowService.getMultiple([
    'regions_enabled',
    'regions',
    'authentication',
    'authenticated',
    'cust',
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

  // Safety functions for icon props
  const getIconCollection = (jurisdiction: Jurisdiction | null): string => {
    return jurisdiction?.icon?.collection || 'fa6-solid';
  };

  const getIconName = (jurisdiction: Jurisdiction | null): string => {
    return jurisdiction?.icon?.name || 'globe';
  };
</script>

<template>
  <div
    v-if="displayMasthead"
    class="w-full">
    <div class="flex flex-col items-center justify-between sm:flex-row">

    <div class="mb-4 flex items-center justify-between sm:mb-0">
        <router-link
          to="/"
          class="group flex items-center"
          aria-label="Onetime Secret Homepage">
          <div class="relative">
            <img
              id="logo"
              src="@/assets/img/onetime-logo-v3-xl.svg"
              class="size-12 rounded-md transition-transform sm:size-16"
              height="64"
              width="64"
              alt="" />
              <Menu
                v-if="jurisdictionStore.enabled"
                as="div"
                class="relative">
                <MenuButton
                  class="absolute -right-0.5 -bottom-0.5 rounded px-0.5 py-0 text-[0.6em]
                         font-brand font-medium bg-brand-500 text-brand-100
                         border border-brand-100 dark:border-slate-800
                         dark:bg-slate-800 dark:text-slate-100">
                  {{ currentJurisdiction?.identifier }}
                </MenuButton>
                <transition
                  enter-active-class="transition duration-100 ease-out"
                  enter-from-class="transform scale-95 opacity-0"
                  enter-to-class="transform scale-100 opacity-100"
                  leave-active-class="transition duration-75 ease-in"
                  leave-from-class="transform scale-95 opacity-100"
                  leave-to-class="transform scale-95 opacity-0">
                  <MenuItems
                    class="absolute z-10 mt-1 -right-2 w-max min-w-[200px] origin-top-right
                           rounded-lg bg-white dark:bg-gray-800 px-2 py-1 text-xs
                           shadow-lg ring-1 ring-black ring-opacity-5
                           divide-y divide-gray-200 dark:divide-gray-700">
                    <div class="py-2">
                      <p class="text-gray-500 dark:text-gray-400">Current Jurisdiction</p>
                      <div class="flex items-center font-medium text-gray-900 dark:text-white">
                        <OIcon :collection="getIconCollection(currentJurisdiction)"
                               :name="getIconName(currentJurisdiction)"
                               class="mr-2 size-5"
                               aria-hidden="true" />
                        <span>{{ currentJurisdiction?.display_name }}</span>
                      </div>
                    </div>
                    <div class="py-2">
                      <div class="px-3 py-2 font-brand text-xs font-semibold uppercase tracking-wider text-gray-700 dark:text-gray-100">
                        Regions
                      </div>
                      <MenuItem v-for="jurisdiction in jurisdictionStore.jurisdictions"
                               v-slot="{ active }"
                               :key="jurisdiction.identifier">
                        <a :href="`https://${jurisdiction.domain}/`"
                           :title="`Continue to ${jurisdiction.domain}`"
                           :class="[
                             active ? 'bg-gray-100 dark:bg-gray-700 text-gray-900 dark:text-white' :
                                     'text-gray-700 dark:text-gray-300',
                             'group flex w-full items-center rounded-md px-2 py-2 text-sm'
                           ]">
                          <span class="flex items-center">
                            <OIcon :collection="getIconCollection(jurisdiction)"
                                   :name="getIconName(jurisdiction)"
                                   class="mr-2 size-5"
                                   aria-hidden="true" />
                            <span class="block truncate"
                                  :class="{ 'font-semibold': currentJurisdiction?.identifier === jurisdiction.identifier }">
                              {{ jurisdiction.display_name }}
                            </span>
                          </span>
                          <span v-if="currentJurisdiction?.identifier === jurisdiction.identifier"
                                class="ml-auto text-brand-500">
                            ✓
                          </span>
                        </a>
                      </MenuItem>
                    </div>
                  </MenuItems>
                </transition>
              </Menu>
          </div>
          <div class="ml-3 flex flex-col">
            <span class="font-brand text-xl font-bold tracking-tight text-gray-900 dark:text-white">
              Onetime Secret
            </span>
            <span class="text-xs text-gray-500 dark:text-gray-400">
            Signed. Sealed. Delivered.<sup class="text-[0.7em] text-gray-500 dark:text-gray-400 [animation:pulse_4s_ease-in-out_infinite]">*</sup>
            </span>
          </div>
        </router-link>
      </div>

      <nav
        v-if="displayNavigation"
        role="navigation"
        aria-label="Main navigation"
        class="flex flex-wrap items-center justify-center gap-4 font-brand text-sm sm:justify-end sm:text-base">
        <template v-if="windowProps.authenticated && windowProps.cust">
          <HeaderUserNav
            :cust="windowProps.cust"
            :colonel="colonel" />

          <button
            @click="openSettingsModal"
            class="text-xl text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white"
            aria-label="Settings">
            <OIcon
              class="size-5"
              collection="material-symbols"
              name="settings" />
          </button>

          <SettingsModal
            :is-open="isSettingsModalOpen"
            @close="closeSettingsModal" />

          <span
            class="text-gray-400"
            aria-hidden="true"
            role="separator">
            |
          </span>

          <router-link
            to="/logout"
            class="text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white"
            :title="$t('web.COMMON.header_logout')"
            :aria-label="$t('web.COMMON.header_logout')">
            <OIcon
              class="size-5"
              collection="heroicons"
              name="arrow-right-on-rectangle-solid" />
          </router-link>
        </template>

        <template v-else>
          <template v-if="windowProps.authentication.enabled">
            <router-link
              v-if="windowProps.authentication.signup"
              to="/signup"
              title="Signup - Individual and Business plans"
              class="font-bold text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
              {{ $t('web.COMMON.header_create_account') }}
            </router-link>
            <span
              class="text-gray-400"
              aria-hidden="true"
              role="separator">
              |
            </span>
            <router-link
              to="/about"
              title="About Onetime Secret"
              class="text-gray-600 transition-colors duration-200 hover:text-gray-800 dark:text-gray-300 dark:hover:text-white">
              {{ $t('web.COMMON.header_about') }}
            </router-link>
            <span
              class="text-gray-400"
              aria-hidden="true"
              role="separator">
              |
            </span>
            <router-link
              v-if="windowProps.authentication.signin"
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
</template>
