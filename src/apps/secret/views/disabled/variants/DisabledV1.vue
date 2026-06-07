<!-- src/apps/secret/views/disabled/variants/DisabledV1.vue -->

<script setup lang="ts">
  import MonotoneJapaneseSecretButtonIcon from '@/shared/components/icons/MonotoneJapaneseSecretButtonIcon.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import type { DisabledHomepageProps } from '../useDisabledConfig';
  import { computed, ref, watch } from 'vue';

  /*
    V1 — "Composed refresh" of the disabled-homepage view.

    Renders the same hero composition for both branded (custom domain with
    configured brand) and unbranded (canonical / free-tier custom domain)
    contexts, swapping logo, headline copy, and promo visibility from props.

    Purely presentational — all data, feature flags, and href targets come
    from props supplied by `useDisabledConfig` in the dispatcher.
  */

  const props = defineProps<DisabledHomepageProps>();

  // Image error handling for branded logos that may 404. Reset whenever the
  // logo URL changes so a subsequent valid URL gets a chance to load.
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

  const monogramStyle = computed(() => ({ backgroundColor: props.primaryColor }));
  // Always emit the dot's accent color from primaryColor so branded mode
  // uses the workspace color and unbranded falls back to OTS orange. Avoids
  // the stale hard-coded shadow color in the static class fallback.
  const dotStyle = computed(() => {
    const color = props.isBranded ? props.primaryColor : '#dc4a22';
    return { backgroundColor: color, boxShadow: `0 0 8px ${color}` };
  });
</script>

<template>
  <div class="relative mx-auto flex w-full max-w-2xl flex-col items-center px-4 pb-12 pt-16 text-center sm:pt-24">
    <!-- Mark — priority: configured custom-domain logo → branded monogram → OTS mark -->
    <div class="mb-8 flex items-center justify-center">
      <img
        v-if="hasUsableLogo"
        :src="logoUri ?? ''"
        :alt="$t('homepage_secrets.disabled.logo_alt', { name: workspaceName })"
        class="h-24 w-auto max-w-[180px] object-contain"
        @error="onLogoError" />
      <div
        v-else-if="isBranded"
        :style="monogramStyle"
        class="flex size-28 items-center justify-center rounded-3xl font-brand text-6xl font-extrabold tracking-tight text-white shadow-sm"
        aria-hidden="true">
        {{ monogramInitial }}
      </div>
      <div
        v-else
        class="flex size-28 items-center justify-center rounded-3xl bg-brand-500 text-white shadow-sm dark:bg-brand-600"
        aria-hidden="true">
        <MonotoneJapaneseSecretButtonIcon
          :size="76"
          class="text-white" />
      </div>
    </div>

    <!-- Eyebrow badge -->
    <span
      class="inline-flex items-center gap-2 text-xs font-bold uppercase tracking-[0.15em] text-brand-700 dark:text-brand-400">
      <span
        class="size-[7px] rounded-full"
        :style="dotStyle"
        aria-hidden="true"></span>
      <template v-if="isBranded">
        {{ $t('homepage_secrets.disabled.private_instance_eyebrow') }}
      </template>
      <template v-else>
        {{ $t('homepage_secrets.disabled.members_only_eyebrow') }}
      </template>
    </span>

    <!-- Headline -->
    <h1
      class="mt-5 max-w-2xl text-balance font-brand text-4xl font-extrabold leading-[1.05] tracking-tight text-gray-900 dark:text-white sm:text-5xl">
      <i18n-t
        v-if="isBranded"
        keypath="homepage_secrets.disabled.team_link_headline"
        tag="span"
        scope="global">
        <template #workspace>
          <em class="font-bold italic">{{ workspaceName }}</em>
        </template>
      </i18n-t>
      <i18n-t
        v-else
        keypath="homepage_secrets.disabled.signin_headline"
        tag="span"
        scope="global">
        <template #action>
          <em class="font-bold italic">{{
            $t('homepage_secrets.disabled.signin_headline_action')
          }}</em>
        </template>
      </i18n-t>
    </h1>

    <!-- Subtitle -->
    <p class="mt-5 max-w-xl text-pretty text-base leading-relaxed text-gray-600 dark:text-gray-300 sm:text-lg">
      <template v-if="isBranded">
        {{ $t('homepage_secrets.disabled.team_subtitle', { domain: displayDomain }) }}
      </template>
      <template v-else>
        {{ $t('homepage_secrets.disabled.public_subtitle') }}
      </template>
    </p>

    <!-- CTA row -->
    <div class="mt-9 inline-flex flex-wrap items-center justify-center gap-x-6 gap-y-3">
      <router-link
        v-if="showSignin"
        to="/signin"
        data-testid="disabled-homepage-signin"
        class="inline-flex items-center gap-2 rounded-xl bg-brand-600 px-7 py-3.5 font-sans text-[15px] font-semibold text-white shadow-sm transition-colors hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:focus:ring-offset-gray-900">
        {{ $t('homepage_secrets.disabled.signin_cta') }}
        <OIcon
          collection="heroicons"
          name="arrow-right"
          class="size-4" />
      </router-link>
      <a
        v-if="showWhatIsThis && whatIsThisHref"
        :href="whatIsThisHref"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center gap-1.5 rounded-md text-sm font-semibold text-gray-500 transition-colors hover:text-gray-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:text-gray-400 dark:hover:text-gray-200 dark:focus:ring-offset-gray-900">
        <OIcon
          collection="heroicons"
          name="information-circle"
          class="size-4" />
        {{ $t('homepage_secrets.disabled.what_is_this') }}
        <span class="sr-only">{{ $t('homepage_secrets.disabled.opens_in_new_tab') }}</span>
      </a>
    </div>

    <!-- Trust strip — verifiable claims only. Do not add "end-to-end
         encrypted" here: the product does not implement E2EE. -->
    <div class="mt-12 w-full max-w-xl border-t border-gray-200 pt-6 dark:border-gray-700">
      <div class="flex flex-wrap items-center justify-center gap-x-7 gap-y-3">
        <span class="inline-flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
          <OIcon
            collection="heroicons"
            name="eye"
            class="size-4 text-gray-600 dark:text-gray-300" />
          {{ $t('homepage_secrets.disabled.trust_viewed_once') }}
        </span>
        <span class="inline-flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
          <OIcon
            collection="heroicons"
            name="server-stack"
            class="size-4 text-gray-600 dark:text-gray-300" />
          {{ $t('homepage_secrets.disabled.trust_zero_retained') }}
        </span>
      </div>
    </div>

    <!-- Promo (free-tier visitors on an unbranded custom domain, SaaS only) -->
    <div
      v-if="showPromo && promoHref"
      class="mt-6 inline-flex max-w-xl items-center gap-3 rounded-2xl border border-dashed border-gray-300 bg-gray-50 px-4 py-3 text-left dark:border-gray-700 dark:bg-gray-800/40">
      <span
        class="inline-flex size-9 flex-shrink-0 items-center justify-center rounded-lg border border-brandcomp-500/30 bg-brandcomp-500/10 text-brandcomp-600 dark:text-brandcomp-400">
        <OIcon
          collection="heroicons"
          name="sparkles"
          class="size-5" />
      </span>
      <div class="text-sm leading-snug">
        <div class="font-semibold text-gray-900 dark:text-white">
          {{ $t('homepage_secrets.disabled.promo_title') }}
        </div>
        <div class="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
          {{ $t('homepage_secrets.disabled.promo_subtitle') }}
          <a
            :href="promoHref"
            target="_blank"
            rel="noopener noreferrer"
            class="ml-1 rounded-sm font-semibold text-brand-700 hover:underline focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:text-brand-400 dark:focus:ring-offset-gray-900">
            {{ $t('homepage_secrets.disabled.promo_learn_how') }} &rarr;
            <span class="sr-only">{{ $t('homepage_secrets.disabled.opens_in_new_tab') }}</span>
          </a>
        </div>
      </div>
    </div>
  </div>
</template>
