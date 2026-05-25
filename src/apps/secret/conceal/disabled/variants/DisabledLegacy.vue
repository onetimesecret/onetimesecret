<!-- src/apps/secret/conceal/disabled/variants/DisabledLegacy.vue -->

<script setup lang="ts">
  import DisabledHomepageTaglines from '@/apps/secret/components/conceal/DisabledHomepageTaglines.vue';
  import type { DisabledHomepageProps } from '../useDisabledConfig';

  /*
    Legacy — the original two-tagline placeholder.

    Kept as a rollback target for the V1 refresh. Renders the same
    `DisabledHomepageTaglines` component the `disabled-ui` mode still uses,
    so behaviour is identical to the pre-refresh AccessDenied.

    Accepts the full DisabledHomepageProps contract for compatibility with
    the dispatcher, but only consumes what it needs.
  */

  // eslint-disable-next-line @typescript-eslint/no-unused-vars -- the legacy
  // variant ignores most of the new props bag; the destructure documents
  // the contract it accepts.
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
