<script setup>
import OIcon from '@/components/icons/OIcon.vue';

defineProps({
  success: String,
  error: String
});
</script>

<template>
  <div class="dark:bg-gray-800">
    <div
      v-if="error"
      class="mb-4 rounded-md bg-red-50 p-4 dark:bg-red-900">
      <div class="mb-8 flex">
        <div class="shrink-0">
          <OIcon
            collection="mdi"
            name="fire-circle"
            class="size-5 text-red-400 dark:text-red-300"
            aria-hidden="true"
          />
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-red-800 dark:text-red-100">
            {{ $t('web.COMMON.error') }}
          </h3>
          <div class="mt-2 text-sm text-red-700 dark:text-red-200">
            <p>{{ error }}</p>
          </div>
        </div>
      </div>
    </div>

    <div
      v-if="success"
      class="mb-4 rounded-md bg-green-50 p-4 dark:bg-green-900">
      <div class="mb-8 flex">
        <div class="shrink-0">
          <OIcon
            collection="mdi"
            name="check-circle"
            class="size-5 text-green-400 dark:text-green-300"
            aria-hidden="true"
          />
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-green-800 dark:text-green-100">
            {{ $t('web.STATUS.success') }}
          </h3>
          <div class="mt-2 text-sm text-green-700 dark:text-green-200">
            <p>{{ success }}</p>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
