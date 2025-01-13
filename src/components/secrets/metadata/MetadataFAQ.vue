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
  <!-- F.A.Q (if show_secret) -->
  <div v-if="details.show_secret" class="space-y-6 text-sm text-gray-600 dark:text-gray-400">
    <div class="flex items-center justify-between">
      <h3 class="text-lg font-semibold text-gray-800 dark:text-gray-200">F.A.Q.</h3>
      <div class="rounded-md bg-blue-50 dark:bg-blue-900/20 px-3 py-1">
        Expires in {{ record.natural_expiration }}
      </div>
    </div>

    <div class="space-y-4">
      <h4 class="font-semibold">Core Security Features</h4>

      <div class="rounded-lg bg-gray-50 dark:bg-gray-800 p-4">
        <h5 class="font-medium mb-2">One-time Access</h5>
        <p>Each secret can only be viewed once. After viewing, it's permanently deleted from our servers.
           This ensures your sensitive information isn't accidentally exposed through browser history or
           mistakenly shared private links.</p>
      </div>

      <template v-if="details.has_passphrase">
        <div class="rounded-lg bg-gray-50 dark:bg-gray-800 p-4">
          <h5 class="font-medium mb-2">Passphrase Protection</h5>
          <p>Your passphrase is immediately hashed using
            <a href="https://en.wikipedia.org/wiki/Bcrypt"
               class="text-brand-500 hover:underline">bcrypt</a>
            and never stored in its original form. This zero-knowledge approach means we
            can't access or recover your secret - only someone with the correct passphrase can.</p>
        </div>
      </template>

      <div>
        <h5 class="font-medium mb-2">What happens when I burn a secret?</h5>
        <p>Burning a secret permanently deletes it before anyone can read it. The recipient will see a
           message indicating the secret doesn't exist. This is useful if you accidentally share the
           wrong information or need to prevent access.</p>
      </div>

      <div>
        <h5 class="font-medium mb-2">Why can I only see the secret value once?</h5>
        <p>We display the value for you so that you can verify it but we do that once so that if someone
           gets this private page (in your browser history or if you accidentally send the private link
           instead of the secret one), they won't see the secret value.</p>
      </div>
    </div>
  </div>

  <!-- F.A.Q (if not show_secret) -->
  <div v-else class="space-y-6 text-sm text-gray-600 dark:text-gray-400">
    <div class="flex items-center justify-between">
      <h3 class="text-lg font-semibold text-gray-800 dark:text-gray-200">F.A.Q.</h3>
      <div class="rounded-md bg-blue-50 dark:bg-blue-900/20 px-3 py-1">
        Expires in {{ record.natural_expiration }}
      </div>
    </div>

    <template v-if="!details.show_secret_link">
      <div class="rounded-lg bg-gray-50 dark:bg-gray-800 p-4">
        <h5 class="font-medium mb-2">Lost your secret link?</h5>
        <p>For security reasons, we can't recover lost secret links. You'll need to create a new secret
           and generate a new link. We recommend copying the link immediately after creation.</p>
      </div>
    </template>

    <div>
      <h5 class="font-medium mb-2">How does secret expiration work?</h5>
      <p>Your secret will remain available for {{ record.natural_expiration }} or until it's viewed,
         whichever comes first. After either condition is met, the secret is permanently deleted.</p>
    </div>

    <div>
      <h5 class="font-medium mb-2">What's the burn feature?</h5>
      <p>The burn feature lets you permanently delete a secret before anyone views it. This is useful
         if you need to revoke access or shared the wrong information. Once burned, the secret cannot
         be recovered.</p>
    </div>

    <div class="mt-6 text-xs">
      <p>Have more questions? Visit our
        <a :href="`${windowProps.support_host}/docs`" class="text-brand-500 hover:underline">documentation</a> or
        <a href="/feedback" class="text-brand-500 hover:underline">send feedback</a>.
      </p>
    </div>
  </div>
</template>
