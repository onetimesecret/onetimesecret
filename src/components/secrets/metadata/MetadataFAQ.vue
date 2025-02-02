<script setup lang="ts">
import { Metadata, MetadataDetails } from '@/schemas/models';
import { WindowService } from '@/services/window.service';

const windowProps = WindowService.getMultiple([
  'support_host',
]);

interface Props {
  record: Metadata;
  details: MetadataDetails;
}

defineProps<Props>()
</script>

<template>
  <div>
    <!-- F.A.Q (if show_secret) -->
    <div v-if="details.show_secret" class="space-y-6 text-sm text-gray-600 dark:text-gray-400">
      <div class="flex items-center justify-between">
        <h3 class="text-lg font-semibold text-gray-800 dark:text-gray-200">F.A.Q.</h3>
        <div class="rounded-md bg-blue-50 dark:bg-blue-900/20 px-3 py-1">
          {{ $t('web.private.expires-in-record-natural_expiration', [record.natural_expiration]) }}
        </div>
      </div>

      <div class="space-y-4">
      <h4 class="font-semibold text-gray-900 dark:text-gray-100">{{ $t('web.private.core-security-features') }}</h4>


      <div class="rounded-lg bg-gray-50 dark:bg-gray-800/50 p-4 ring-1 ring-gray-200 dark:ring-gray-700">
        <h5 class="font-medium mb-2 text-gray-900 dark:text-gray-100">{{ $t('web.private.one-time-access') }}</h5>
          <p>{{ $t('web.private.each-secret-can-only-be-viewed-once-after-viewin') }}</p>
        </div>

        <template v-if="details.has_passphrase">
          <div class="rounded-lg bg-gray-50 dark:bg-gray-800/50 p-4 ring-1 ring-gray-200 dark:ring-gray-700">
            <h5 class="font-medium mb-2 text-gray-900 dark:text-gray-100">{{ $t('web.private.passphrase-protection') }}</h5>
            <a href="https://en.wikipedia.org/wiki/Bcrypt"
              class="text-blue-600 hover:text-blue-700 dark:text-blue-400 dark:hover:text-blue-300">bcrypt</a>
              {{ $t('web.private.and-never-stored-in-its-original-form-this-appro') }}
          </div>
        </template>

        <div class="rounded-lg bg-gray-50 dark:bg-gray-800/50 p-4 ring-1 ring-gray-200 dark:ring-gray-700">
              <h5 class="font-medium mb-2 text-gray-900 dark:text-gray-100">{{ $t('web.private.what-happens-when-i-burn-a-secret') }}</h5>
          <p>{{ $t('web.private.burning-a-secret-permanently-deletes-it-before-a') }}</p>
        </div>

        <div class="rounded-lg bg-gray-50 dark:bg-gray-800/50 p-4 ring-1 ring-gray-200 dark:ring-gray-700">
              <h5 class="font-medium mb-2 text-gray-900 dark:text-gray-100">{{ $t('web.private.why-can-i-only-see-the-secret-value-once') }}</h5>
          <p>{{ $t('web.private.we-display-the-value-for-you-so-that-you-can-ver') }}</p>
        </div>
      </div>
    </div>

    <!-- F.A.Q (if not show_secret) -->
    <div v-else class="space-y-6 text-sm text-gray-600 dark:text-gray-400">
      <div class="flex items-center justify-between">
        <h3 class="text-lg font-semibold text-gray-800 dark:text-gray-200">F.A.Q.</h3>
        <div class="rounded-md bg-blue-50 dark:bg-blue-900/20 px-3 py-1">
          {{ $t('web.private.expires-in-record-natural_expiration-0', [record.natural_expiration]) }}
        </div>
      </div>

      <template v-if="!details.show_secret_link">
      <div class="rounded-lg bg-gray-50 dark:bg-gray-800/50 p-4 ring-1 ring-gray-200 dark:ring-gray-700">
            <h5 class="font-medium mb-2 text-gray-900 dark:text-gray-100">{{ $t('web.private.lost-your-secret-link') }}</h5>
          <p>{{ $t('web.private.for-security-reasons-we-cant-recover-lost-secret') }}</p>
        </div>
      </template>

      <div class="rounded-lg bg-gray-50 dark:bg-gray-800/50 p-4 ring-1 ring-gray-200 dark:ring-gray-700">
            <h5 class="font-medium mb-2 text-gray-900 dark:text-gray-100">{{ $t('web.private.how-does-secret-expiration-work') }}</h5>
        <p>{{ $t('web.private.your-secret-will-remain-available-for-record-nat', [record.natural_expiration]) }}</p>
      </div>

      <div class="rounded-lg bg-gray-50 dark:bg-gray-800/50 p-4 ring-1 ring-gray-200 dark:ring-gray-700">
            <h5 class="font-medium mb-2 text-gray-900 dark:text-gray-100">{{ $t('web.private.whats-the-burn-feature') }}</h5>
        <p>{{ $t('web.private.the-burn-feature-lets-you-permanently-delete-a-s') }}</p>
      </div>

    </div>
    <div class="mt-6 text-xs">
      <p>{{ $t('web.private.have-more-questions-visit-our') }}
        <a :href="`${windowProps.support_host}/docs`" class="text-blue-600 hover:text-blue-700 dark:text-blue-400 dark:hover:text-blue-300 hover:underline">documentation</a> or
        <a href="/feedback" class="text-blue-600 hover:text-blue-700 dark:text-blue-400 dark:hover:text-blue-300 hover:underline">{{ $t('web.private.send-feedback') }}</a>.
      </p>
    </div>
  </div>
</template>
