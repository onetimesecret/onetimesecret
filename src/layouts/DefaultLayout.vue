
<script setup lang="ts">
import GlobalBroadcast from '@/components/GlobalBroadcast.vue';
import FeedbackForm from '@/components/FeedbackForm.vue';
import LanguageToggle from '@/components/LanguageToggle.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import { Icon } from '@iconify/vue';

const shrimp = window.shrimp;
const onetimeVersion = window.ot_version;
const cust = window.cust;

interface Props {
  displayMasthead: boolean
  authenticated: boolean
  colonel: boolean
  defaultLocale: string
  authentication: {
    enabled: boolean
    signup: boolean
    signin: boolean
  }
  isDefaultLocale: boolean
}

withDefaults(defineProps<Props>(), {
  displayMasthead: true,
  authenticated: false,
  colonel: false,
  defaultLocale: 'en',
  authentication: () => ({
    enabled: true,
    signup: true,
    signin: true
  }),
  isDefaultLocale: true
})
</script>

<template>
  <div>

    <div class="w-full h-1 bg-brand-500 fixed top-0 left-0"></div>
    <GlobalBroadcast :show="false" content="" />

    <!-- Your header content -->
    <header>
      <div class="container mx-auto mt-1 p-2 max-w-2xl">
        <div v-if="displayMasthead" class="min-w-[320px]">
          <div class="flex flex-col sm:flex-row justify-between items-center">
            <div class="mb-6 sm:mb-0"><a href="/"><img id="logo" src="@/assets/img/onetime-logo-v3-xl.svg" class="" width="64" height="64" alt="Logo"></a></div>
            <nav class="flex flex-wrap justify-center sm:justify-end items-center gap-2 text-base font-brand">

              <template v-if="authenticated">
                <div class="hidden sm:flex items-center">
                  <a href="/" class="text-gray-400 hover:text-gray-300 transition">
                    <span id="userEmail">{{ cust.custid }}</span>
                  </a>
                  <a v-if="colonel" href="/colonel/" title="" class="ml-2 text-gray-400 hover:text-gray-300 transition">
                    <Icon icon="mdi:star" class="w-4 h-4" />
                  </a>
                  <span class="mx-2 text-gray-400">|</span>
                </div>

                <a href="/account" class="underline" title="Your Account">{{ $t('web.COMMON.header_dashboard') }}</a> <span class="mx-0 text-gray-400">|</span>
                <a href="/logout" class="underline" title="Log out of Onetime Secret">{{ $t('web.COMMON.header_logout') }}</a>
              </template>

              <template v-else>
                <template v-if="authentication.enabled">
                  <a v-if="authentication.signup" href="/signup" title="Signup - Individual and Business plans" class="underline font-bold mx-0 px-0">{{ $t('web.COMMON.header_create_account') }}</a><span class="mx-0">|</span>
                  <a href="/about" title="About Onetime Secret" class="underline">{{ $t('web.COMMON.header_about') }}</a><span class="mx-0">|</span>

                  <a v-if="authentication.signin" href="/signin" title="Log in to Onetime Secret" class="underline">{{ $t('web.COMMON.header_sign_in') }}</a>
                </template>

                <a v-else href="/about" title="About Onetime Secret" class="underline">{{ $t('web.COMMON.header_about') }}</a>
              </template>

              <template v-if="!isDefaultLocale">
                <span class="mx-0">|</span> <a :href="`?locale=${defaultLocale}`" :title="`View site in ${defaultLocale}`">{{ defaultLocale }}</a>
              </template>

            </nav>
          </div>
        </div>
      </div>
    </header>
    <main class="container mx-auto p-4 max-w-2xl">
      <slot></slot>
    </main>

    <!-- Your footer content -->
    <div class="container mx-auto p-4 max-w-2xl">
      <footer class="min-w-[320px] text-sm text-center space-y-2">

        <div>
          <FeedbackForm :shrimp="shrimp" :showRedButton="false" />
        </div>

        <!-- Dark mode toggle in t  he bottom left corner -->
        <div class="fixed bottom-4 left-4 z-50">
          <div class="mt-2 text-slate-300">
            <ThemeToggle />
          </div>
        </div>

        <!-- Languages dropdown in the bottom right corner -->
        <div class="fixed text-left bottom-4 right-4 z-50 opacity-60 hover:opacity-100" aria-label="Change language">
          <div class="relative">

            <LanguageToggle
              :isDefaultLocale="false"
              currentLocale="en"
              :supportedLocales="['en', 'fr', 'es']"
            />

          </div>
        </div>

        <div v-if="onetimeVersion" class="text-gray-400 dark:text-gray-500 mt-4 pt-4">
          v{{onetimeVersion}}
        </div>

      </footer>
    </div>
  </div>
</template>
