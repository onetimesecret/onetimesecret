<!-- src/apps/secret/views/disabled/variants/DisabledLegacy.vue -->

<script setup lang="ts">
  import DisabledHomepageTaglines from '@/apps/secret/components/conceal/DisabledHomepageTaglines.vue';
  import type { DisabledHomepageProps } from '../useDisabledConfig';

  /*
    Legacy — the original two-tagline placeholder.

    Kept as a rollback target for the V1 refresh. Renders the same
    `DisabledHomepageTaglines` component the `disabled-ui` mode still uses,
    so behaviour is identical to the pre-refresh DisabledHomepage.

    Accepts the full DisabledHomepageProps contract for compatibility with
    the dispatcher, but only consumes what it needs.
  */

  // Legacy variant ignores the props bag entirely — kept for contract
  // compatibility with the dispatcher. The `_` prefix matches the project's
  // unused-vars lint allowlist.
  const _props = defineProps<DisabledHomepageProps>();
</script>

<template>
  <div class="flex flex-col items-center px-4 pt-24 sm:pt-32">
    <div class="container mx-auto min-w-[320px] max-w-2xl">
      <DisabledHomepageTaglines
        :tagline1="$t('web.homepage.authonly.tagline1')"
        :tagline2="$t('web.homepage.authonly.tagline2')"
        class="mb-6" />
      <div class="mb-6"></div>
    </div>
  </div>
</template>
