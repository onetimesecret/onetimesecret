<!-- src/apps/secret/components/branded/BrandedHero.vue -->

<script setup lang="ts">
  /**
   * THE branded hero: brand logo + headline + subline, stacked and centered,
   * shared by every custom-domain surface that opens with the brand identity.
   * The heading binds headingFontClass and the body binds fontFamilyClass —
   * reading the store here (not via props) means that within the hero the
   * heading token is bound once and call sites cannot rebind it. (Surfaces
   * that preview an arbitrary domain, like the dashboard's SecretPreview,
   * intentionally resolve their own tokens instead of using this component.)
   * Do not fork this markup into page-local variants.
   *
   * Title and subtitle are optional: omit both for a logo-only opener. The
   * reveal/confirm case does this — it renders the brand logo at the top like
   * every other surface but keeps its own "You have a message" heading and
   * instructions, so the hero here must not duplicate them.
   *
   * @prop title - Headline text (already translated); omit for logo-only
   * @prop subtitle - Subline text (already translated); omit for logo-only
   * @prop logoLinkTo - When set, wraps the logo in a router-link to this route
   */
  import { useProductIdentity } from '@/shared/stores/identityStore';
  import { storeToRefs } from 'pinia';
  import { ref } from 'vue';
  import { RouterLink } from 'vue-router';

  defineProps<{
    title?: string;
    subtitle?: string;
    logoLinkTo?: string;
  }>();

  const identityStore = useProductIdentity();
  const { logoUri, displayName, cornerClass, headingFontClass, fontFamilyClass } =
    storeToRefs(identityStore);

  // Handle logo 404 errors gracefully
  const imageError = ref(false);
  const handleImageError = () => {
    imageError.value = true;
  };
</script>

<template>
  <div
    :class="fontFamilyClass"
    class="text-center">
    <!-- Logo with error handling - hides if 404. No placeholder: a broken or
         absent logo must not render a generic gray icon on a branded page. -->
    <!--
      Sizing: a fixed height with `w-auto max-w-full` lets wide, rectangular
      logos (common when they include the company name) use the full column
      width instead of being squeezed by a narrow max-width and rendering
      comically small.

      Corner radius: the logo reflects the brand radius (cornerClass) — a
      product requirement. The browser clamps `--radius-brand` to half the
      image's shorter side, so a pill/full radius rounds the ends rather than
      overflowing.
    -->
    <div
      v-if="logoUri && !imageError"
      class="mb-8 flex justify-center">
      <!-- One <img>, conditionally wrapped: forked link/bare copies of the
           logo markup drift independently (only one branch gets a fix). -->
      <component
        :is="logoLinkTo ? RouterLink : 'span'"
        :to="logoLinkTo">
        <img
          :src="logoUri"
          :class="cornerClass"
          class="h-16 w-auto max-w-full object-contain sm:h-20"
          :alt="displayName"
          @error="handleImageError" />
      </component>
    </div>
    <h1
      v-if="title"
      :class="headingFontClass"
      class="text-2xl font-semibold text-gray-900 dark:text-white">
      {{ title }}
    </h1>
    <p
      v-if="subtitle"
      class="mt-2 text-gray-600 dark:text-gray-300">
      {{ subtitle }}
    </p>
  </div>
</template>
