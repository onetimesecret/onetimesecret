<script setup lang="ts">
import { WindowService } from '@/services/window.service';

interface Props {
  displayPoweredBy: boolean;
}
defineProps<Props>();

const siteHost = WindowService.get('site_host');
</script>

<template>
  <div>
    <div class="bg-white dark:bg-gray-900">
      <div class="mx-auto max-w-7xl px-4 py-12 sm:px-6 sm:py-16 lg:px-8">
        <div class="text-center">
          <h2
            class="text-base font-semibold
            uppercase tracking-wide
            text-brandcomp-700 opacity-40 dark:text-brandcomp-600">
            {{ $t('onetime-secret') }}
          </h2>
          <h3
            class="mt-1 text-3xl font-extrabold
              text-gray-500 dark:text-gray-300
              sm:text-3xl sm:tracking-tight lg:text-4xl">
            {{ $t('youve-got-secret-mail') }}
          </h3>
          <p
            class="mx-auto mt-5 max-w-xl text-xl
              text-gray-400 dark:text-gray-400">
            {{ $t('a-secure-one-time-message-awaits-you') }} <br />
            {{ $t('before-you-open-it-heres-what-you-should-know') }}
          </p>
        </div>
      </div>
    </div>
    <div class="bg-white dark:bg-gray-900">
      <div class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8 lg:py-12">
        <div class="lg:grid lg:grid-cols-3 lg:gap-8">
          <div>
            <h3 class="text-lg font-medium text-gray-600 dark:text-white">
              {{ $t('what-is-this') }}
            </h3>
            <p class="mt-3 text-base text-gray-400 dark:text-gray-300">
              {{ $t('onetime-secret-is-a-secure-way-to-share-sensitiv') }}
            </p>
          </div>
          <div class="mt-8 lg:mt-0">
            <h3 class="text-lg font-medium text-gray-600 dark:text-white">
              {{ $t('is-it-secure') }}
            </h3>
            <p class="mt-3 text-base text-gray-400 dark:text-gray-300">
              {{ $t('yes-after-viewing-the-secret-is-permanently-dele') }}
            </p>
          </div>
          <div class="mt-8 lg:mt-0">
            <h3 class="text-gray6900 whitespace-nowrap text-lg font-medium dark:text-white">
              {{ $t('what-happens-next') }}
            </h3>
            <p class="mt-3 text-base text-gray-400 dark:text-gray-300">
              {{ $t('when-ready-click-the-view-secret-button-at-the-t') }}
            </p>
          </div>
        </div>
      </div>
    </div>

    <div class="pt-20 text-center text-xs text-gray-400 dark:text-gray-600">
      <div class="space-x-2">
        <a
          v-if="displayPoweredBy"
          :href="`https://${siteHost}`"
          class="hover:underline"
          rel="noopener noreferrer">
          {{ $t('powered-by-onetime-secret') }}
        </a>
        <span v-if="displayPoweredBy">.</span>
        <router-link
          to="/info/terms"
          class="hover:underline">
          {{ $t('terms') }}
        </router-link>
        <span>.</span>
        <router-link
          to="/info/privacy"
          class="hover:underline">
          {{ $t('privacy') }}
        </router-link>
      </div>
    </div>
  </div>
</template>
