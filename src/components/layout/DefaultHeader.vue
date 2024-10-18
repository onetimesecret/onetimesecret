<template>
  <header>
    <div class="container mx-auto px-4 py-2 min-w-[320px] max-w-2xl">
      <div v-if="displayMasthead"
           class="w-full">
        <div class="flex flex-col sm:flex-row justify-between items-center">
          <div class="mb-6 sm:mb-0 self-start">
            <router-link to="/">
              <img id="logo"
                   src="@/assets/img/onetime-logo-v3-xl.svg"
                   class="rounded-md"
                   aria-label="Onetime Secret"
                   width="64"
                   height="64"
                   alt="Logo">
            </router-link>
          </div>

          <nav v-if="displayNavigation"
               class="flex flex-wrap justify-center sm:justify-end items-center gap-2 text-base font-brand">
            <template v-if="authenticated && cust">
              <HeaderUserNav :cust="cust"
                             :colonel="colonel" />
              <a href="#"
                 @click="openSettingsModal"
                 class="underline"
                 title="Your Account">{{ $t('web.COMMON.header_settings') }}</a>

              <SettingsModal :is-open="isSettingsModalOpen"
                             @close="closeSettingsModal" />

              <span class="mx-0 text-gray-400">|</span>
              <router-link to="/logout"
                           class="underline"
                           title="Log out of Onetime Secret">{{ $t('web.COMMON.header_logout') }}</router-link>
            </template>

            <template v-else>
              <template v-if="authentication.enabled">
                <router-link v-if="authentication.signup"
                             to="/signup"
                             title="Signup - Individual and Business plans"
                             class="underline font-bold mx-0 px-0">{{ $t('web.COMMON.header_create_account') }}</router-link><span
                      class="mx-0">|</span>
                <router-link to="/about"
                             title="About Onetime Secret"
                             class="underline">{{ $t('web.COMMON.header_about') }}</router-link><span
                      class="mx-0">|</span>

                <router-link v-if="authentication.signin"
                             to="/signin"
                             title="Log in to Onetime Secret"
                             class="underline">{{ $t('web.COMMON.header_sign_in') }}</router-link>
              </template>

              <router-link v-else
                           to="/about"
                           title="About Onetime Secret"
                           class="underline">{{ $t('web.COMMON.header_about') }}</router-link>
            </template>
          </nav>
        </div>
      </div>
    </div>
  </header>
</template>

<script setup lang="ts">
import HeaderUserNav from '@/components/layout/HeaderUserNav.vue';
import SettingsModal from '@/components/modals/SettingsModal3.vue';
import type { Props as BaseProps } from '@/layouts/BaseLayout.vue';
import { computed, ref } from 'vue';

// Define the props for this layout, extending the BaseLayout props
export interface Props extends BaseProps {
  displayMasthead?: boolean
  displayNavigation?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  // Haaland all features by default. These can be overridden by the
  // route.meta.layoutProps object or in the layout components
  // themselves. This prevents the header and footer from being
  // displayed on pages where they are not needed, esp in the ca
  // case where a slow connection causes the default layout to
  // be displayed before the route-specific layout is loaded.
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
