<template>
  <div>
    <div class="bg-white dark:bg-gray-900">
      <div class="mx-auto max-w-7xl px-4 py-12 sm:px-6 sm:py-16 lg:px-8">
        <div class="text-center">
          <h2
            class="text-base font-semibold
            uppercase tracking-wide
            text-brandcomp-700 opacity-40 dark:text-brandcomp-600">
            Onetime Secret
          </h2>
          <h3
            class="mt-1 text-3xl font-extrabold
              text-gray-500 dark:text-gray-300
              sm:text-3xl sm:tracking-tight lg:text-4xl">
            You've got (secret) mail
          </h3>
          <p
            class="mx-auto mt-5 max-w-xl text-xl
              text-gray-400 dark:text-gray-400">
            A secure, one-time message awaits you. <br />
            Before you open it, here's what you should know:
          </p>
        </div>
      </div>
    </div>
    <div class="bg-white dark:bg-gray-900">
      <div class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8 lg:py-12">
        <div class="lg:grid lg:grid-cols-3 lg:gap-8">
          <div>
            <h3 class="text-lg font-medium text-gray-600 dark:text-white">
              What is this?
            </h3>
            <p class="mt-3 text-base text-gray-400 dark:text-gray-300">
              Onetime Secret is a secure way to share sensitive information that self-destructs
              after a single viewing.
            </p>
          </div>
          <div class="mt-8 lg:mt-0">
            <h3 class="text-lg font-medium text-gray-600 dark:text-white">
              Is it secure?
            </h3>
            <p class="mt-3 text-base text-gray-400 dark:text-gray-300">
              Yes. After viewing, the secret is permanently deleted from our servers, ensuring your
              privacy.
            </p>
          </div>
          <div class="mt-8 lg:mt-0">
            <h3 class="text-gray6900 whitespace-nowrap text-lg font-medium dark:text-white">
              What happens next?
            </h3>
            <p class="mt-3 text-base text-gray-400 dark:text-gray-300">
              When ready, click the "View Secret" button at the top of the page to reveal your
              one-time message.
            </p>
          </div>
        </div>
      </div>
    </div>

    <div class="pt-20 text-center text-xs text-gray-400 dark:text-gray-600">
      <div class="space-x-2">
        <a
          :href="`https://${siteHost}`"
          class="hover:underline"
          rel="noopener noreferrer">
          Powered by Onetime Secret
        </a>
        <span>·</span>
        <router-link
          to="/info/terms"
          class="hover:underline">
          Terms
        </router-link>
        <span>·</span>
        <router-link
          to="/info/privacy"
          class="hover:underline">
          Privacy
        </router-link>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { useWindowProp } from '@/composables/useWindowProps';

const siteHost = useWindowProp('site_host');
</script>
