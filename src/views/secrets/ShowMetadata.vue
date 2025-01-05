
<script setup lang="ts">
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import ErrorDisplay from '@/components/ErrorDisplay.vue'
import BurnButtonForm from '@/components/secrets/metadata/BurnButtonForm.vue';
import MetadataDisplayCase from '@/components/secrets/metadata/MetadataDisplayCase.vue';
import MetadataFAQ from '@/components/secrets/metadata/MetadataFAQ.vue';
import SecretLink from '@/components/secrets/metadata/SecretLink.vue';
import { useMetadata } from '@/composables/useMetadata';
import { onMounted, onUnmounted, watch } from 'vue';

// Define props
interface Props {
  metadataKey: string,
}
const props = defineProps<Props>();

const { record, details, isLoading, fetch, error, reset } = useMetadata(props.metadataKey);

// Watch for route parameter changes to refetch data
watch(
  () => props.metadataKey,
  (newKey) => {
    reset();
    if (newKey) {
      fetch();
    }
  }
);

onMounted(() => {
  fetch();
});

// Ensure cleanup when component unmounts
onUnmounted(() => {
  reset();
});
</script>

<template>
  <div class="mx-auto max-w-4xl px-4">
    <DashboardTabNav />

    <ErrorDisplay v-if="error" :error="error" />

    <!-- Loading State -->
    <div v-if="isLoading" class="py-8 text-center text-gray-600">
      <span class="">Loading...</span>
    </div>

    <div v-else-if="record && details" class="space-y-8">
      <!-- Primary Content Section -->
      <div class="space-y-6">
        <SecretLink
          v-if="details.show_secret_link"
          :metadata="record"
          :details="details"
        />

        <h3
          v-if="details.show_recipients"
          class="mb-4 text-lg font-semibold text-gray-800 dark:text-gray-200">
          {{ $t('web.COMMON.sent_to') }} {{ record.recipients }}
        </h3>

        <MetadataDisplayCase
          :metadata="record"
          :details="details"
          class="shadow-sm"
        />

        <BurnButtonForm
          :metadata="record"
          :details="details"
          class="pt-2"
        />
      </div>

      <!-- Recipients Section -->
      <div
        v-if="details.show_recipients"
        class="border-t border-gray-100 py-4 dark:border-gray-800">
        <h3 class="text-lg font-semibold text-gray-800 dark:text-gray-200">
          {{ $t('web.COMMON.sent_to') }} {{ record.recipients }}
        </h3>
      </div>

      <!-- Create Another Secret -->
      <div class="pt-6">
        <a
          href="/"
          class="
            mx-auto
            mb-24
            mt-12
            block
            w-2/3
            rounded-md
            border-2
            border-gray-300
            bg-gray-200
            px-4
            py-2
            text-center
            text-base
            font-medium
            text-gray-800
            hover:border-gray-200
            hover:bg-gray-100
            dark:border-gray-800
            dark:bg-gray-700
            dark:text-gray-200
            dark:hover:border-gray-600
            dark:hover:bg-gray-600
          ">
          Create another secret
        </a>
      </div>

      <!-- FAQ Section -->
      <MetadataFAQ
        :metadata="record"
        :details="details"
        class="border-t border-gray-100 pt-8 dark:border-gray-800"
      />
    </div>
  </div>
</template>
