<!-- src/apps/secret/conceal/AccessDenied.vue -->

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
    `bootstrap.disabled_homepage` without a frontend release. New variants:
    add the component, register it here, and add its name to
    `disabledHomepageVariantSchema`.

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
  const ActiveVariant = computed(() => VARIANTS[variant] ?? DisabledV1);
</script>

<template>
  <component
    :is="ActiveVariant"
    v-bind="props" />
</template>
