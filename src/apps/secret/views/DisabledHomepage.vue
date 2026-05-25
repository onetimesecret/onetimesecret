<!-- src/apps/secret/views/DisabledHomepage.vue -->

<script setup lang="ts">
  import type { DisabledHomepageVariant } from '@/schemas/contracts/disabled-homepage';
  import { computed, type Component } from 'vue';
  import DisabledLegacy from './disabled/variants/DisabledLegacy.vue';
  import DisabledMinimal from './disabled/variants/DisabledMinimal.vue';
  import DisabledV1 from './disabled/variants/DisabledV1.vue';
  import { useDisabledConfig } from './disabled/useDisabledConfig';

  /*
    Disabled-homepage dispatcher.

    Shown when UI is enabled but the homepage secret form is gated by
    authentication (auth required, or homepage mode is "external"). Picks a
    visual variant from bootstrap config and renders it with a single
    presentational props bag derived in `useDisabledConfig`.

    Operators can flip the variant or override individual feature flags via
    `bootstrap.disabled_homepage` without a frontend release. Adding a new
    variant requires touching three places:
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
    legacy: DisabledLegacy,
  };

  const { variant, props } = useDisabledConfig();
  // Fallback to v1 covers the (statically unreachable) case where bootstrap
  // carries a variant id the frontend doesn't recognise — e.g. backend
  // emits a new variant before the matching component ships.
  const ActiveVariant = computed(() => VARIANTS[variant.value] ?? DisabledV1);
</script>

<template>
  <component
    :is="ActiveVariant"
    v-bind="props" />
</template>
