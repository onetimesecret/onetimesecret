<!-- src/shared/components/logos/BrandMark.vue -->

<script setup lang="ts">
  import { computed, ref, watch, type StyleValue } from 'vue';

  /*
    BrandMark — the shared light/dark logo pair with a graceful fallback.

    Renders the light logo (hidden in dark mode when a dark variant exists)
    plus the optional dark-theme variant, swapped via the app's class-based
    `dark:` utilities so it tracks the theme toggle, not the OS scheme.

    A logo that 404s is treated as absent: an internal @error flag (reset
    whenever the URL changes so a subsequent valid URL gets a chance to
    load) flips rendering to the `fallback` slot. Consumers put their own
    monogram/keyhole/placeholder markup there — the slot boundary guarantees
    the fallback only appears when no usable logo exists.

    Sizing/styling is the consumer's job via `imgClass` (applied to both
    imgs so the light/dark pair always match) and optional `imgStyle` /
    `height` for pixel-accurate callers (MastHead). Extra attrs (e.g. `id`)
    land on the light img only.
  */

  defineOptions({ inheritAttrs: false });

  const props = withDefaults(
    defineProps<{
      /** Light-theme logo URL. Null/empty renders the fallback slot. */
      logoUri: string | null;
      /** Dark-theme logo URL; when set, the light img gets `dark:hidden`. */
      logoDarkUri?: string | null;
      /** Accessible name, shared by both imgs. */
      alt: string;
      /** Sizing/layout classes applied to both light and dark imgs. */
      imgClass?: string | (string | null)[] | null;
      /** Inline style for both imgs (explicit pixel sizing callers). */
      imgStyle?: StyleValue;
      /** `height` attribute for both imgs. */
      height?: number;
    }>(),
    {
      logoDarkUri: null,
      imgClass: null,
      imgStyle: undefined,
      height: undefined,
    }
  );

  // Image error handling for logos that may 404. Reset whenever the logo URL
  // changes so a subsequent valid URL gets a chance to load.
  const logoError = ref(false);
  watch(
    () => props.logoUri,
    () => {
      logoError.value = false;
    }
  );
  const onLogoError = () => {
    logoError.value = true;
  };
  const hasUsableLogo = computed(() => !!props.logoUri && !logoError.value);
</script>

<template>
  <template v-if="hasUsableLogo">
    <img
      v-bind="$attrs"
      :src="logoUri ?? ''"
      :alt="alt"
      :class="[imgClass, logoDarkUri ? 'dark:hidden' : null]"
      :style="imgStyle"
      :height="height"
      @error="onLogoError" />
    <!-- Dark-theme logo variant (brand.logo_dark_url): swapped by the
         app's class-based dark mode so it tracks the theme toggle. -->
    <img
      v-if="logoDarkUri"
      data-testid="logo-dark"
      :src="logoDarkUri"
      :alt="alt"
      :class="['hidden dark:block', imgClass]"
      :style="imgStyle"
      :height="height" />
  </template>
  <slot
    v-else
    name="fallback"></slot>
</template>
