<!-- src/apps/secret/views/disabled/variants/DisabledMinimal.vue -->

<script setup lang="ts">
  import KeyholeIcon from '@/shared/components/icons/KeyholeIcon.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import type { DisabledHomepageProps } from '../useDisabledConfig';
  import { computed, ref, watch } from 'vue';

  /*
    Minimal — a quiet refresh of the closed two-tagline view.

    Same visual restraint as the original (small mark, single column,
    no promo, no trust strip, no eyebrow), but with refreshed copy and a
    proper sign-in CTA so visitors aren't left guessing what to do.

    Shares the same i18n keys as V1 — only the chrome differs.
  */

  const props = defineProps<DisabledHomepageProps>();

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
</script>

<template>
  <div class="mx-auto flex w-full max-w-xl flex-col items-center px-4 pb-12 pt-20 text-center sm:pt-28">
    <!-- Small mark — priority: configured custom-domain logo → branded monogram → neutral keyhole mark -->
    <div class="mb-6 flex items-center justify-center">
      <img
        v-if="hasUsableLogo"
        :src="logoUri ?? ''"
        :alt="$t('homepage_secrets.disabled.logo_alt', { name: workspaceName })"
        class="h-12 w-auto max-w-[120px] object-contain"
        @error="onLogoError" />
      <div
        v-else-if="isBranded"
        :style="monogramStyle"
        :class="[cornerClass ?? 'rounded-2xl', fontFamilyClass ?? 'font-brand']"
        class="flex size-14 items-center justify-center text-2xl font-extrabold tracking-tight text-white"
        aria-hidden="true">
        {{ monogramInitial }}
      </div>
      <div
        v-else
        class="flex size-14 items-center justify-center rounded-2xl bg-brand-500 text-white dark:bg-brand-600"
        aria-hidden="true">
        <KeyholeIcon
          :size="36"
          class="text-white" />
      </div>
    </div>

    <!-- Headline (smaller than V1, larger than closed) -->
    <h1
      :class="fontFamilyClass ?? 'font-brand'"
      class="text-balance text-2xl font-bold leading-tight tracking-tight text-gray-800 dark:text-gray-100 sm:text-3xl">
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
    <p class="mt-3 max-w-md text-pretty text-sm leading-relaxed text-gray-600 dark:text-gray-400">
      <template v-if="isBranded">
        {{ $t('homepage_secrets.disabled.team_subtitle', { domain: displayDomain }) }}
      </template>
      <template v-else>
        {{ $t('homepage_secrets.disabled.public_subtitle') }}
      </template>
    </p>

    <!-- CTA row (ghost button, smaller than V1) -->
    <div class="mt-6 inline-flex flex-wrap items-center justify-center gap-x-5 gap-y-2">
      <!-- One-click SSO: skip /signin and POST straight to the provider when
           SSO is the only login method and a single provider is configured. -->
      <button
        v-if="ssoOneClick"
        type="button"
        data-testid="disabled-homepage-sso"
        :class="cornerClass ?? 'rounded-lg'"
        class="inline-flex items-center gap-2 border border-gray-300 bg-white px-5 py-2 text-sm font-semibold text-gray-800 cursor-pointer shadow-sm transition-colors hover:border-gray-400 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-100 dark:hover:border-gray-600 dark:hover:bg-gray-800 dark:focus:ring-offset-gray-900"
        @click="onSsoLogin">
        {{
          ssoProviderName
            ? $t('web.login.sign_in_with_provider', { provider: ssoProviderName })
            : $t('homepage_secrets.disabled.signin_cta')
        }}
        <OIcon
          collection="heroicons"
          name="arrow-right"
          class="size-4" />
      </button>
      <router-link
        v-else-if="showSignin"
        to="/signin"
        data-testid="disabled-homepage-signin"
        :class="cornerClass ?? 'rounded-lg'"
        class="inline-flex items-center gap-2 border border-gray-300 bg-white px-5 py-2 text-sm font-semibold text-gray-800 transition-colors hover:border-gray-400 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-100 dark:hover:border-gray-600 dark:hover:bg-gray-800 dark:focus:ring-offset-gray-900">
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
        class="rounded-sm text-sm font-medium text-gray-500 hover:text-gray-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:text-gray-400 dark:hover:text-gray-200 dark:focus:ring-offset-gray-900">
        {{ $t('homepage_secrets.disabled.what_is_this') }}
        <span class="sr-only">{{ $t('homepage_secrets.disabled.opens_in_new_tab') }}</span>
      </a>
    </div>
  </div>
</template>
