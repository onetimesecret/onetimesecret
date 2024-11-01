<template>
  <div>
    <div class="bg-white dark:bg-gray-900">
      <div class="max-w-7xl mx-auto py-12 px-4 sm:py-16 sm:px-6 lg:px-8">
        <div class="text-center">
          <h2
              class="text-base font-semibold
            text-brandcomp-700 dark:text-brandcomp-600
            tracking-wide uppercase opacity-40">
            Onetime Secret
          </h2>
          <h3
              class="mt-1 text-3xl font-extrabold
              text-gray-500 dark:text-gray-300
              sm:text-3xl sm:tracking-tight lg:text-4xl">
            You've got (secret) mail
          </h3>
          <p
              class="max-w-xl mt-5 mx-auto text-xl
              text-gray-400 dark:text-gray-400">
            A secure, one-time message awaits you. <br>
            Before you open it, here's what you should know:
          </p>
        </div>
      </div>
    </div>
    <div class="bg-white dark:bg-gray-900">
      <div class="max-w-7xl mx-auto py-8 px-4 sm:px-6 lg:py-12 lg:px-8">
        <div class="lg:grid lg:grid-cols-3 lg:gap-8">
          <div>
            <h3 class="text-lg font-medium text-gray-600 dark:text-white">What is this?</h3>
            <p class="mt-3 text-base text-gray-400 dark:text-gray-300">
              Onetime Secret is a secure way to share sensitive information that self-destructs
              after a single viewing.
            </p>
          </div>
          <div class="mt-8 lg:mt-0">
            <h3 class="text-lg font-medium text-gray-600 dark:text-white">Is it secure?</h3>
            <p class="mt-3 text-base text-gray-400 dark:text-gray-300">
              Yes. After viewing, the secret is permanently deleted from our servers, ensuring your
              privacy.
            </p>
          </div>
          <div class="mt-8 lg:mt-0">
            <h3 class="text-lg font-medium text-gray6900 dark:text-white whitespace-nowrap">
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

    <div class="text-center pt-20 text-xs text-gray-400 dark:text-gray-600">
      <div class="space-x-2">
        <a :href="`https://${siteHost}`"
           class="hover:underline"
           rel="noopener noreferrer">
          Powered by Onetime Secret
        </a>
        <span>·</span>
        <router-link to="/info/terms" class="hover:underline">Terms</router-link>
        <span>·</span>
        <router-link to="/info/privacy" class="hover:underline">Privacy</router-link>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { useWindowProp } from '@/composables/useWindowProps';
const siteHost = useWindowProp('site_host');
</script>
