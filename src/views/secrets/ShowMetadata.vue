<!--
The metadata page has distinct states with specific visual priorities
and transitions, primarily based on the parameters and state of the
secret.

1. Viewable (Initial State - New)
   - Emerald color scheme
   - Shows absolute URL to the secret link
   - Shows actual secret content (unless the secret is protected by passphrase)
   - Displays "New secret created successfully!"
   - Emphasizes "you will only see this once"
   - Prominently shows expiration timing

2. Protected (After Page Refresh)
   - Amber color scheme
   - Hides secret content with bullet points
   - Hides URL to the secret link (unless the user is the owner of the metadata/secret)
   - Shows "Encrypted" status OR "Encrypted with passphrase"
   - Maintains expiration timing display

3. Received (After Recipient Receives the secret content)
   - Gray color scheme
   - Shows "Received X time ago" message
   - Secret content is permanently removed (it is literally deleted from the database and not recoverable)
   - Keeps creation/received timestamps

4. Burned (Manual Destruction)
   - Red color scheme
   - Shows "Burned X time ago" message
   - Secret content is permanently removed
   - Hides all "Encrypted" status text
   - Maintains burn timestamp

5. Destroyed (Terminal State)
   - Red color scheme
   - Combines received/burned/orphan states
   - Shows appropriate timing information based on update timestamp
   - No access to secret content

Each state transition is one-way and permanent, with visual elements
like (icons, colors, messages) carefully designed to communicate the
secret's current status and history.
-->

<script setup lang="ts">
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import ErrorDisplay from '@/components/ErrorDisplay.vue'
import BurnButtonForm from '@/components/secrets/metadata/BurnButtonForm.vue';
import MetadataDisplayCase from '@/components/secrets/metadata/MetadataDisplayCase.vue';
import MetadataFAQ from '@/components/secrets/metadata/MetadataFAQ.vue';
import SecretLink from '@/components/secrets/metadata/SecretLink.vue';
import { useMetadata } from '@/composables/useMetadata';
import { onMounted } from 'vue';
import { onBeforeRouteUpdate } from 'vue-router';

// Define props
interface Props {
  metadataKey: string,
}
const props = defineProps<Props>();

const { record, details, isLoading, fetch } = useMetadata(props.metadataKey);

onBeforeRouteUpdate((to, from, next) => {
  console.debug('[ShowMetadata] Route updating', to.params.metadataKey);
  fetch();
  next();
});

onMounted(fetch);
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
