<!-- src/apps/secret/views/disabled/variants/DisabledClosed.vue -->

<script setup lang="ts">
  import DisabledHomepageTaglines from '@/apps/secret/components/conceal/DisabledHomepageTaglines.vue';
  import type { DisabledHomepageProps } from '../useDisabledConfig';

  /*
    Closed — the quiet two-tagline placeholder (the default).

    Renders the same `DisabledHomepageTaglines` component the `disabled-ui`
    mode still uses, so behaviour is identical to the pre-refresh
    DisabledHomepage: a plain "members only" notice with no sign-in CTA.

    Accepts the full DisabledHomepageProps contract for compatibility with
    the dispatcher, but only consumes what it needs.
  */

  // Closed variant ignores the props bag entirely — kept for contract
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
