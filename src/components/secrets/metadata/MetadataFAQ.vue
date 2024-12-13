<script setup lang="ts">
import { Metadata, MetadataDetails } from '@/schemas/models'
import { defineProps } from 'vue'

interface Props {
  metadata: Metadata;
  details: MetadataDetails;
}

defineProps<Props>()
</script>

<template>
  <!-- F.A.Q (if show_secret) -->
  <div
    v-if="details.show_secret"
    class="text-sm text-gray-600 dark:text-gray-400">
    <h3 class="mb-2 text-lg font-semibold text-gray-800 dark:text-gray-200">
      F.A.Q.
    </h3>
    <template v-if="details.has_passphrase">
      <h4 class="mb-2 mt-4 font-semibold">
        Why can't I see my passphrase?
      </h4>
      <p class="mb-4">
        We can't show it to you because we don't know what it is. When you create a secret with a
        passphrase, we immediately hash it with
        <a
          href="https://en.wikipedia.org/wiki/Bcrypt"
          class="text-brand-500 hover:underline">bcrypt</a>. Since we don't store the passphrase, we have no way to show it to you. That also means when
        you include a passphrase, we have no way to decrypt your secret.
      </p>

      <h4 class="mb-2 mt-4 font-semibold">
        Why can't I see the secret value?
      </h4>
      <p class="mb-4">
        We display the value for you so that you can verify it but we do that once so that if someone
        gets this private page (in your browser history or if you accidentally send the private link
        instead of the secret one), they won't see the secret value.
      </p>
    </template>

    <h4 class="mb-2 mt-4 font-semibold">
      What happens when I burn a secret?
    </h4>
    <p class="mb-4">
      Burning a secret will delete it before it has been read. If you send someone a secret link and
      burn the secret before they view it, they will not be able to read it. In fact, it will look
      to them like the secret never existed at all.
    </p>

    <h4 class="mb-2 mt-4 font-semibold">
      Why can I only see the secret value once?
    </h4>
    <p class="mb-4">
      We display the value for you so that you can verify it but we do that once so that if someone
      gets this private page (in your browser history or if you accidentally send the private link
      instead of the secret one), they won't see the secret value.
    </p>

    <h4 class="mb-2 mt-4 font-semibold">
      How long will the secret be available?
    </h4>
    <p class="mb-4">
      The secret link will be available for {{ metadata.expiration_stamp }} or until it's viewed.
    </p>
  </div>

  <!-- F.A.Q (if not show_secret) -->
  <div
    v-else
    class="text-sm text-gray-600 dark:text-gray-400">
    <h3 class="mb-2 text-lg font-semibold text-gray-800 dark:text-gray-200">
      F.A.Q.
    </h3>
    <template v-if="!details.show_secret_link">
      <h4 class="mb-2 mt-4 font-semibold">
        What if I forgot to copy the shared link?
      </h4>
      <p class="mb-4">
        You need to create a new secret. We can't retrieve it for you.
      </p>
    </template>

    <h4 class="mb-2 mt-4 font-semibold">
      How long will the secret be available?
    </h4>
    <p class="mb-4">
      The secret link will be available for {{ metadata.expiration_stamp }} or until it's viewed.
    </p>

    <h4 class="mb-2 mt-4 font-semibold">
      What happens when I burn a secret?
    </h4>
    <p class="mb-4">
      Burning a secret will delete it before it has been read. If you send someone a secret link and
      burn the secret before they view it, they will not be able to read it. In fact, it will look
      to them like the secret never existed at all.
    </p>
  </div>
</template>
