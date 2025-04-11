<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';

defineProps({
  success: [String, Array],
  error: [String, Array],
  errors: {
    type: Array as () => string[],
    default: () => []
  }
});
</script>

<template>
  <div class="dark:bg-gray-800">
    <div
      v-if="error || errors.length > 0"
      class="mb-4 rounded-md bg-red-50 p-4 dark:bg-red-900">
      <div class="flex">
        <div class="shrink-0">
          <OIcon
            collection="mdi"
            name="fire-circle"
            class="size-5 text-red-400 dark:text-red-300"
            aria-hidden="true"
          />
        </div>
        <div class="ml-3 flex-1">
          <h3 class="text-sm font-medium text-red-800 dark:text-red-100">
            {{ $t('web.COMMON.error') }}
          </h3>
          <div class="mt-2 text-sm text-red-700 dark:text-red-200">
            <!-- Single error string -->
            <p v-if="error && typeof error === 'string'">{{ error }}</p>

            <!-- Array of errors -->
            <ul v-else-if="errors.length > 0 || (error && Array.isArray(error))" class="list-disc pl-5 space-y-1">
              <li v-for="(err, index) in errors.length > 0 ? errors : error" :key="index">{{ err }}</li>
            </ul>
          </div>
        </div>
      </div>
    </div>

    <div
      v-if="success"
      class="mb-4 rounded-md bg-green-50 p-4 dark:bg-green-900">
      <div class="flex">
        <div class="shrink-0">
          <OIcon
            collection="mdi"
            name="check-circle"
            class="size-5 text-green-400 dark:text-green-300"
            aria-hidden="true"
          />
        </div>
        <div class="ml-3 flex-1">
          <h3 class="text-sm font-medium text-green-800 dark:text-green-100">
            {{ $t('web.STATUS.success') }}
          </h3>
          <div class="mt-2 text-sm text-green-700 dark:text-green-200">
            <!-- Single success message -->
            <p v-if="typeof success === 'string'">{{ success }}</p>

            <!-- Array of success messages -->
            <ul v-else-if="Array.isArray(success)" class="list-disc pl-5 space-y-1">
              <li v-for="(msg, index) in success" :key="index">{{ msg }}</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
