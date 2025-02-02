<!--src/views/secrets/UnknownMetadata.vue-->

<script setup lang="ts">
  import BaseUnknownSecret from '@/components/base/BaseUnknownSecret.vue';
  import OIcon from '@/components/icons/OIcon.vue';
</script>

<template>
<BaseUnknownSecret
  :branded="false"
  class="my-14">
  <template #header="{}">
    <div class="mb-8 flex justify-center items-center flex-col">
      <OIcon
        collection="heroicons"
        name="question-mark-circle-16-solid"
        class="w-16 h-16 mb-6 text-red-500 dark:text-red-400"
        aria-hidden="true" />
      <h1
        class="mb-6 text-3xl font-bold text-gray-800 dark:text-white text-center"
        aria-label="$t('information-no-longer-available')">
        {{ $t('that-information-is-no-longer-available') }}
      </h1>
    </div>
  </template>
    <template #action="{}">
      <div class="flex justify-center items-center">
        <!-- Canonical action button -->
        <router-link
          to="/"
          :class="[
            'inline-block rounded-lg border-2 transition duration-300 ease-in-out',
            'bg-white dark:bg-gray-800',
            'hover:bg-brand-100 dark:hover:bg-gray-700',
            'focus:outline-none focus:ring-2 focus:ring-offset-2 dark:focus:ring-offset-gray-900',
            'focus:ring-brand-500 dark:focus:ring-brand-400',
            'px-6 py-3 font-brand text-lg hover:border-brand-600 dark:hover:border-brand-400',
          ]"
          :style="{
            color: 'var(--color-brand-500)',
            borderColor: 'var(--color-brand-500)',
          }"
          aria-label="$t('return-to-home-page')">
          {{ $t('return-to-home') }}
        </router-link>
      </div>
    </template>
  </BaseUnknownSecret>
</template>
