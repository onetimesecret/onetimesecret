
<script setup lang="ts">
import GlobalBroadcast from '@/components/GlobalBroadcast.vue';
import FeedbackForm from '@/components/FeedbackForm.vue';
import LanguageToggle from '@/components/LanguageToggle.vue';
import ThemeToggle from '@/components/ThemeToggle.vue';
import { Icon } from '@iconify/vue';
import { AuthenticationSettings, Cust } from '@/types/onetime';

export interface Props {
  authenticated: boolean
  authentication: AuthenticationSettings
  colonel: boolean
  cust?: Cust
  defaultLocale: string
  displayFeedback: boolean
  displayLinks: boolean
  displayMasthead: boolean
  displayVersion: boolean
  isDefaultLocale: boolean
  onetimeVersion: string
  plansEnabled?: boolean
  supportHost?: string
}

withDefaults(defineProps<Props>(), {
  authenticated: false,
  colonel: false,
  defaultLocale: 'en',
  isDefaultLocale: true,
})

</script>

<template>
  <div>

    <div class="w-full h-1 bg-brand-500 fixed top-0 left-0 z-50"></div>
    <GlobalBroadcast :show="false" content="" />

    <!-- Header content -->
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

              <template v-if="!isDefaultLocale">
                <span class="mx-0">|</span> <router-link :to="`?locale=${defaultLocale}`" :title="`View site in ${defaultLocale}`">{{ defaultLocale }}</router-link>
              </template>

            </nav>
          </div>
        </div>
      </div>
    </header>

    <!-- Slot for main content -->
    <slot name="main"></slot>

    <!-- Footer content -->
    <footer class="min-w-[320px] text-sm text-center space-y-2">
      <div class="container mx-auto p-4 max-w-2xl">

        <div v-if="displayFeedback">
          <FeedbackForm :showRedButton="false" />
        </div>

        <div v-if="displayLinks" class="prose dark:prose-invert text-base pt-4 font-brand">
          <template v-if="supportHost">
            <a :href="`${supportHost}/blog`" aria-label="Our blogging website" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100" rel="noopener noreferrer">Blog</a> |
          </template>

          <template v-if="plansEnabled">
            <router-link to="/pricing" aria-label="Onetime Secret Subscription Pricing" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100">
              Pricing
            </router-link> |
          </template>

          <a href="https://github.com/onetimesecret/onetimesecret" aria-label="View source code on GitHub" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100" rel="noopener noreferrer">GitHub</a> |

          <template v-if="supportHost">
            <a :href="`${supportHost}/docs/rest-api`" aria-label="Our documentation site (in beta)" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100" rel="noopener noreferrer">API</a> |
            <a :href="`${supportHost}/docs`" aria-label="Our documentation site (in beta)" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100" rel="noopener noreferrer">Docs</a>
          </template>
        </div>
        <div v-if="displayLinks" class="prose dark:prose-invert text-base font-brand">
          <router-link to="/info/privacy" aria-label="Read our Privacy Policy" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100">
            Privacy
          </router-link> |
          <router-link to="/info/terms" aria-label="Read our Terms and Conditions" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100">
            Terms
          </router-link> |
          <router-link to="/info/security" aria-label="View security information" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100">
            Security
          </router-link> |
          <a href="https://status.onetimesecret.com/" aria-label="Check service status" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100" rel="noopener noreferrer">Status</a> |
          <a :href="`${supportHost}/about`" aria-label="About Onetime Secret" class="text-gray-700 dark:text-gray-300 hover:text-gray-900 dark:hover:text-gray-100">About</a>
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

            <LanguageToggle />

          </div>
        </div>

        <div v-if="displayVersion" class="text-gray-400 dark:text-gray-500 mt-4 pt-4">
          v{{onetimeVersion}}
        </div>

      </div>
    </footer>
  </div>
</template>
