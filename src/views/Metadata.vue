<script setup lang="ts">
import { defineProps } from 'vue'
import SecretLink from '@/components/secrets/metadata/SecretLink.vue';
import DisplayCase from '@/components/secrets/DisplayCase.vue';
import MetadataFAQ from '@/components/secrets/metadata/MetadataFAQ.vue';


interface Props {

  // Legacy props
  recipients?: string;
  metadataKey?: string;
  secret_shortkey?: string;
  received_date?: string;
  received_date_utc?: string;
  burned_date?: string;
  burned_date_utc?: string;
  created_date_utc?: string;
  expiration_stamp?: string;
}

defineProps<Props>()

</script>

<template>
  <div>

    <!-- if show_secret_link -->
    <SecretLink>

    </SecretLink>

    <!-- if show_recipients -->
    <h3 class="text-lg font-semibold text-gray-800 dark:text-gray-200 mb-4">
      {{$t('web.COMMON.sent_to')}} {{recipients}}
    </h3>

    <!-- if show_secret -->
    <DisplayCase :metadata-key="metadataKey"></DisplayCase>

    <!-- else -->
    <div class="mb-4">
      <p class="mb-2 text-gray-600 dark:text-gray-400">
        {{$t('web.COMMON.secret')}} ({{secret_shortkey}}):
      </p>
      <input
        class="w-full px-3 py-2 bg-gray-100 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-brand-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
        value="*******************"
        disabled />
    </div>

    <p class="text-gray-600 dark:text-gray-400 mb-4">
      <!--{{#is_received}}-->
      <em>{{$t('web.COMMON.received')}} {{received_date}}.</em>
      <span class="text-sm text-gray-500 dark:text-gray-400">({{received_date_utc}})</span>
      <!--{{/is_received}} {{#is_burned}}-->
      <em>{{$t('web.COMMON.burned')}} {{burned_date}}.</em>
      <span class="text-sm text-gray-500 dark:text-gray-400">({{burned_date_utc}})</span>
      <!--{{/is_burned}} {{^is_destroyed}}-->
      <strong>{{$t('web.COMMON.expires_in')}} {{expiration_stamp}}</strong>.
      <span class="text-sm text-gray-500 dark:text-gray-400">({{created_date_utc}})</span>
      <!--{{/is_destroyed}}-->
    </p>




    <MetadataFAQ />

  </div>
</template>
