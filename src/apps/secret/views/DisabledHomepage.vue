<!-- src/apps/secret/views/DisabledHomepage.vue -->

<script setup lang="ts">
  import type { DisabledHomepageVariant } from '@/schemas/contracts/disabled-homepage';
  import { computed, type Component } from 'vue';
  import DisabledClosed from './disabled/variants/DisabledClosed.vue';
  import DisabledMinimal from './disabled/variants/DisabledMinimal.vue';
  import DisabledV1 from './disabled/variants/DisabledV1.vue';
  import { useDisabledConfig } from './disabled/useDisabledConfig';

  /*
    Disabled-homepage dispatcher.

    Shown when UI is enabled but the homepage secret form is gated by
    authentication (auth required, or homepage mode is "external"). Picks a
    visual variant from per-domain config and renders it with a single
    presentational props bag derived in `useDisabledConfig`.

    Variant resolution (see useDisabledConfig):
      1. `?variant` URL override (dogfood / preview)
      2. `homepage_config.disabled_homepage_variant` for the active domain
      3. `DEFAULT_DISABLED_HOMEPAGE_VARIANT` frontend constant

    Adding a new variant requires touching three places:
      1. drop the component under `disabled/variants/`,
      2. register it in the VARIANTS map below,
      3. add its name to `disabledHomepageVariantSchema` in
         `src/schemas/contracts/disabled-homepage.ts`.

    Audiences:
    - Recipients who arrived via a shared link and may be curious
    - Team members who need to sign in
    - Admins verifying the gated landing page
  */

  const VARIANTS: Record<DisabledHomepageVariant, Component> = {
    v1: DisabledV1,
    minimal: DisabledMinimal,
    closed: DisabledClosed,
  };

  const { variant, props } = useDisabledConfig();
  // Fall back to a known variant if `variant` is ever an unmapped id, so the
  // dispatcher can never resolve to `undefined` (which would render nothing —
  // a blank page). useDisabledConfig already validates, this is defence in depth.
  const ActiveVariant = computed(() => VARIANTS[variant.value] ?? DisabledClosed);
</script>

<template>
  <!--
    Top-left of the page is intentionally empty. Reserved for a future
    canonical brand logo (configured at the deployment level, distinct
    from the per-tenant custom-domain logo which renders at the centre
    of each variant). The disabled-homepage routes hide the layout
    masthead so this area is genuinely free.
  -->
  <div class="flex w-full flex-1 flex-col">
    <component
      :is="ActiveVariant"
      v-bind="props" />
  </div>
</template>
