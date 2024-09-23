<script setup lang="ts">
import { defineProps } from 'vue'
import SecretLink from '@/components/secrets/metadata/SecretLink.vue';
import DisplayCase from '@/components/secrets/DisplayCase.vue';


interface Props {
  metadataKey: string;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const props = defineProps<Props>()

</script>

<template>
  <div>

    <!-- if show_secret_link -->
    <SecretLink>

    </SecretLink>

    <!-- if show_recipients -->
    <h3 class="text-lg font-semibold text-gray-800 dark:text-gray-200 mb-4">
      {{i18n.COMMON.sent_to}} {{recipients}}
    </h3>

    <!-- if show_secret -->
    <DisplayCase :metadata-key="metadataKey"></DisplayCase>

    <!-- else -->
    <div class="mb-4">
      <p class="mb-2 text-gray-600 dark:text-gray-400">
        {{i18n.COMMON.secret}} ({{secret_shortkey}}):
      </p>
      <input
        class="w-full px-3 py-2 bg-gray-100 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-brand-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
        value="*******************"
        disabled />
    </div>

    <p class="text-gray-600 dark:text-gray-400 mb-4">
      <!--{{#is_received}}-->
      <em>{{i18n.COMMON.received}} {{received_date}}.</em>
      <span class="text-sm text-gray-500 dark:text-gray-400">({{received_date_utc}})</span>
      <!--{{/is_received}} {{#is_burned}}-->
      <em>{{i18n.COMMON.burned}} {{burned_date}}.</em>
      <span class="text-sm text-gray-500 dark:text-gray-400">({{burned_date_utc}})</span>
      <!--{{/is_burned}} {{^is_destroyed}}-->
      <strong>{{i18n.COMMON.expires_in}} {{expiration_stamp}}</strong>.
      <span class="text-sm text-gray-500 dark:text-gray-400">({{created_date_utc}})</span>
      <!--{{/is_destroyed}}-->
    </p>

    <!--{{^is_destroyed}}-->
    <a
      href="{{burn_uri}}"
      class="block w-full px-4 py-2 mb-4 text-center text-base bg-yellow-400 rounded-md text-gray-800 hover:bg-yellow-300 focus:outline-none focus:ring-2 focus:ring-yellow-400 focus:ring-offset-2 dark:focus:ring-offset-gray-800">
      <svg
        class="inline-block w-5 h-5 mr-2"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
        xmlns="http://www.w3.org/2000/svg"
        width="20"
        height="20">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M17.657 18.657A8 8 0 016.343 7.343S7 9 9 10c0-2 .5-5 2.986-7C14 5 16.09 5.777 17.656 7.343A7.975 7.975 0 0120 13a7.975 7.975 0 01-2.343 5.657z"></path>
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M9.879 16.121A3 3 0 1012.015 11L11 14H9c0 .768.293 1.536.879 2.121z"></path>
      </svg>
      {{i18n.COMMON.burn_this_secret}}
    </a>

    <p class="text-sm text-gray-500 dark:text-gray-400 mb-4">
      * {{i18n.COMMON.burn_this_secret_hint}}.
    </p>

    <hr class="w-1/4 my-4 mx-auto border-gray-200 dark:border-gray-600" />
    <!--{{/is_destroyed}}-->

    <!-- F.A.Q (if show_secret) -->

    <!-- F.A.Q (if not show_secret) -->

  </div>
</template>
