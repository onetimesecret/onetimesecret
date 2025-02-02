<script setup lang="ts">
  import SecretForm from '@/components/secrets/form/SecretForm.vue';

  import { useProductIdentity } from '@/stores/identityStore';

  const { allowPublicHomepage, primaryColor } = useProductIdentity();
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl py-1 mb-28">

    <SecretForm
      v-if="allowPublicHomepage"
      class="mb-8"
      :with-recipient="false"
      :with-asterisk="false"
      :with-generate="false" />

    <!--
      BrandedHomepage.vue

      Purpose: Landing page for private, white-labeled secure message service instances.

      This page serves two key functions:
      1. Shows the current availability status of the secure messaging service
      2. Provides context for recipients who follow links to the domain

      Key audiences:
      - Recipients: People who received/viewed a secure message and are curious about the service
      - Internal teams: Company employees who need to know how to share sensitive info
      - Admins: People managing the service who need to understand its current state

      Design notes:
      - Maintains professional appearance even when disabled
      - Uses company branding while keeping security/trust as primary focus
      - Messaging must work for all audiences simultaneously since authentication state is unknown
    -->

    <div v-else
      class="bg-white dark:bg-gray-800 rounded-xl shadow-lg overflow-hidden border-t-4"
      :style="{ borderColor: primaryColor }">
      <!-- Brand Identity Section -->
      <!-- <div
        class="border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/50 px-6 py-8">
        <div class="text-center space-y-4">
          <h1
            class="text-2xl font-semibold">
            Title
          </h1>
          <p class="text-base text-gray-600 dark:text-gray-300 max-w-md mx-auto">
          Subtitle
          </p>
        </div>
      </div> -->

      <!-- Main Content Area -->
      <div class="px-6 py-8 bg-white dark:bg-gray-800">
        <!-- Service Status Banner -->
        <div
          class="mb-6 rounded-lg border"
          :style="{
            backgroundColor: `${primaryColor}10`,
            borderColor: `${primaryColor}30`,
          }">
          <div class="px-4 py-4">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <svg
                  class="h-5 w-5"
                  :style="{ color: primaryColor }"
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                  aria-hidden="true">
                  <path
                    fill-rule="evenodd"
                    d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a.75.75 0 000 1.5h.253a.25.25 0 01.244.304l-.459 2.066A1.75 1.75 0 0010.747 15H11a.75.75 0 000-1.5h-.253a.25.25 0 01-.244-.304l.459-2.066A1.75 1.75 0 009.253 9H9z"
                    clip-rule="evenodd" />
                </svg>
              </div>
              <div class="ml-3">
                <p
                  class="text-sm">
                  {{ $t('this-is-a-private-instance-only-authorized-team-') }}
                </p>
              </div>
            </div>
          </div>
        </div>

        <!-- Trust Elements -->
        <div class="space-y-6 text-center">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div class="p-4 rounded-lg bg-gray-50 dark:bg-gray-700/50">
              <div class="flex flex-col items-center space-y-2">
                <svg
                  class="h-6 w-6 text-gray-600 dark:text-gray-300"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z" />
                </svg>
                <p class="text-sm text-gray-600 dark:text-gray-300">
                {{ $t('secure-encrypted-storage') }}
                </p>
              </div>
            </div>
            <div class="p-4 rounded-lg bg-gray-50 dark:bg-gray-700/50">
              <div class="flex flex-col items-center space-y-2">
                <svg
                  class="h-6 w-6 text-gray-600 dark:text-gray-300"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M12 6v6h4.5m4.5 0a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <p class="text-sm text-gray-600 dark:text-gray-300">
                  {{ $t('auto-expire-after-viewing') }}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Footer Information -->
      <!-- <div
        class="border-t border-gray-200 dark:border-gray-700 px-6 py-4 bg-gray-50 dark:bg-gray-800/50">
        <p class="text-sm text-gray-500 dark:text-gray-400 text-center">
          Links from {{ displayDomain }} are managed by {{ name }}.<br />
          Contact your {{ name }} representative to share sensitive information.
        </p>
      </div> -->
    </div>
  </div>

</template>
