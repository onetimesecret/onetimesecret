<!-- src/apps/secret/views/DisabledHomepage.vue -->

<script setup lang="ts">
  import type { DisabledHomepageVariant } from '@/schemas/contracts/disabled-homepage';
  import { DEFAULT_DISABLED_HOMEPAGE_VARIANT } from '@/schemas/contracts/disabled-homepage';
  import { computed, type Component } from 'vue';
  import DisabledLegacy from './disabled/variants/DisabledLegacy.vue';
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
    legacy: DisabledLegacy,
  };

  const { variant, props } = useDisabledConfig();
  // Fallback covers the (statically unreachable) case where the per-domain
  // config carries a variant id the frontend doesn't recognise — e.g.
  // server emits a new variant before the matching component ships. The
  // frontend default is the source of truth for "if we can't dispatch,
  // what do we render?" — keep it in sync with the constant.
  const ActiveVariant = computed(
    () => VARIANTS[variant.value] ?? VARIANTS[DEFAULT_DISABLED_HOMEPAGE_VARIANT]
  );
</script>

<template>
  <!--
    Top-left of the page is intentionally empty. Reserved for a future
    canonical brand logo (configured at the deployment level, distinct
    from the per-tenant custom-domain logo which renders at the centre
    of each variant). The disabled-homepage routes hide the layout
    masthead so this area is genuinely free.
  -->
  <component
    :is="ActiveVariant"
    :data-variant="variant"
    v-bind="props" />
</template>
