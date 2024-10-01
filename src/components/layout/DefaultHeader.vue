<template>
  <header>
    <div class="container mx-auto mt-1 p-2 max-w-2xl">
      <div v-if="displayMasthead" class="min-w-[320px]">
        <div class="flex flex-col sm:flex-row justify-between items-center">
          <div class="mb-6 sm:mb-0"><router-link to="/"><img id="logo" src="@/assets/img/onetime-logo-v3-xl.svg" class="" width="64" height="64" alt="Logo"></router-link></div>
          <nav class="flex flex-wrap justify-center sm:justify-end items-center gap-2 text-base font-brand">

            <template v-if="authenticated && cust">
              <div class="hidden sm:flex items-center">
                <router-link to="/" class="text-gray-400 hover:text-gray-300 transition">
                  <span id="userEmail">{{ cust.custid }}</span>
                </router-link>
                <router-link v-if="colonel" to="/colonel/" title="" class="ml-2 text-gray-400 hover:text-gray-300 transition">
                  <Icon icon="mdi:star" class="w-4 h-4" />
                </router-link>
                <span class="mx-2 text-gray-400">|</span>
              </div>

              <router-link to="/account" class="underline" title="Your Account">{{ $t('web.COMMON.header_dashboard') }}</router-link> <span class="mx-0 text-gray-400">|</span>
              <router-link to="/logout" class="underline" title="Log out of Onetime Secret">{{ $t('web.COMMON.header_logout') }}</router-link>
            </template>

            <template v-else>
              <template v-if="authentication.enabled">
                <router-link v-if="authentication.signup" to="/signup" title="Signup - Individual and Business plans" class="underline font-bold mx-0 px-0">{{ $t('web.COMMON.header_create_account') }}</router-link><span class="mx-0">|</span>
                <router-link to="/about" title="About Onetime Secret" class="underline">{{ $t('web.COMMON.header_about') }}</router-link><span class="mx-0">|</span>

                <router-link v-if="authentication.signin" to="/signin" title="Log in to Onetime Secret" class="underline">{{ $t('web.COMMON.header_sign_in') }}</router-link>
              </template>

              <router-link v-else to="/about" title="About Onetime Secret" class="underline">{{ $t('web.COMMON.header_about') }}</router-link>
            </template>

          </nav>
        </div>
      </div>
    </div>
  </header>
</template>

<script setup lang="ts">
import type { Props as DefaultProps } from '@/layouts/DefaultLayout.vue';
import { Icon } from '@iconify/vue';

// Define the props for this layout, extending the DefaultLayout props
export interface Props extends DefaultProps {
  // Add any additional props specific to this layout
  //additionalProp?: string;

}

withDefaults(defineProps<Props>(), {

});
</script>
